/*
 * Runs ERiC for Abakus as an Erlang port, so that a crash of ERiC cannot take down the BEAM (ADR 0035).
 *
 *   elster <eric home> <log directory>
 *
 * ERiC is loaded with dlopen from <eric home>/lib, never linked or shipped. Requests and answers are packets with a
 * 4-byte big-endian length, each a list of fields, again with a 4-byte length: the command or "ok"/"error" first.
 *
 *   stnr <tax number> <Landesnummer>                 -> ok <tax number in ELSTER's format> | error <message>
 *   send <xml> <Datenart version> <.pfx path> <PIN> <PDF path>
 *                                                    -> ok <server answer> | error <message> <ERiC answer> <server answer>
 *
 * The types follow eric_types.h and ericapi.h of ERiC 44 and later.
 */

#define _POSIX_C_SOURCE 200809L

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __APPLE__
#define ERIC_LIBRARY "libericapi.dylib"
#else
#define ERIC_LIBRARY "libericapi.so"
#endif

#define ERIC_OK 0
#define ERIC_VALIDIERE (1u << 1)
#define ERIC_SENDE (1u << 2)
#define ERIC_DRUCKE (1u << 5)

#define MAX_FIELDS 8
#define MAX_PACKET (64u * 1024u * 1024u)

typedef struct EricReturnBufferApi *EricRueckgabepufferHandle;
typedef uint32_t EricZertifikatHandle;

typedef struct {
  uint32_t version;
  uint32_t vorschau;
  uint32_t duplexDruck;
  const char *pdfName;
  const char *fussText;
  void *pdfCallback;
  void *pdfCallbackBenutzerdaten;
} eric_druck_parameter_t;

typedef struct {
  uint32_t version;
  EricZertifikatHandle zertifikatHandle;
  const char *pin;
} eric_verschluesselungs_parameter_t;

static struct {
  int (*initialisiere)(const char *, const char *);
  int (*beende)(void);
  EricRueckgabepufferHandle (*puffer_erzeugen)(void);
  const char *(*puffer_inhalt)(EricRueckgabepufferHandle);
  int (*puffer_freigeben)(EricRueckgabepufferHandle);
  int (*hole_fehler_text)(int, EricRueckgabepufferHandle);
  int (*make_elster_stnr)(const char *, const char *, const char *, EricRueckgabepufferHandle);
  int (*get_handle_to_certificate)(EricZertifikatHandle *, uint32_t *, const char *);
  int (*close_handle_to_certificate)(EricZertifikatHandle);
  int (*bearbeite_vorgang)(const char *, const char *, uint32_t, const eric_druck_parameter_t *,
                           const eric_verschluesselungs_parameter_t *, EricRueckgabepufferHandle,
                           EricRueckgabepufferHandle);
} eric;

static int out_fd;
static char load_error[512];

typedef struct {
  char *data;
  uint32_t size;
} field_t;

static void wipe(void *data, size_t size) {
  volatile unsigned char *p = data;
  while (size--) *p++ = 0;
}

static int read_exactly(void *buffer, size_t size) {
  char *p = buffer;
  while (size > 0) {
    ssize_t n = read(0, p, size);
    if (n <= 0) return -1;
    p += n;
    size -= (size_t)n;
  }
  return 0;
}

static int write_exactly(const void *buffer, size_t size) {
  const char *p = buffer;
  while (size > 0) {
    ssize_t n = write(out_fd, p, size);
    if (n <= 0) return -1;
    p += n;
    size -= (size_t)n;
  }
  return 0;
}

static void put_length(unsigned char *p, uint32_t n) {
  p[0] = (unsigned char)(n >> 24);
  p[1] = (unsigned char)(n >> 16);
  p[2] = (unsigned char)(n >> 8);
  p[3] = (unsigned char)n;
}

static uint32_t get_length(const unsigned char *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void reply(const char *status, int count, const char **values) {
  uint32_t total = 4 + (uint32_t)strlen(status);
  for (int i = 0; i < count; i++) total += 4 + (uint32_t)strlen(values[i] ? values[i] : "");

  unsigned char *packet = malloc(4 + (size_t)total);
  if (!packet) exit(1);
  unsigned char *p = packet;
  put_length(p, total);
  p += 4;

  const char *parts[MAX_FIELDS + 1];
  parts[0] = status;
  for (int i = 0; i < count; i++) parts[i + 1] = values[i] ? values[i] : "";
  for (int i = 0; i <= count; i++) {
    uint32_t n = (uint32_t)strlen(parts[i]);
    put_length(p, n);
    memcpy(p + 4, parts[i], n);
    p += 4 + n;
  }

  if (write_exactly(packet, 4 + (size_t)total) != 0) exit(1);
  free(packet);
}

static void reply_error(const char *message) { reply("error", 1, &message); }

static void free_fields(field_t *fields, int count) {
  for (int i = 0; i < count; i++) {
    wipe(fields[i].data, fields[i].size);
    free(fields[i].data);
  }
}

static int parse_fields(unsigned char *packet, uint32_t size, field_t *fields) {
  int count = 0;
  uint32_t at = 0;
  while (at < size) {
    if (count == MAX_FIELDS || size - at < 4 || get_length(packet + at) > size - at - 4) {
      free_fields(fields, count);
      return -1;
    }
    uint32_t n = get_length(packet + at);
    at += 4;
    fields[count].data = malloc((size_t)n + 1);
    if (!fields[count].data) exit(1);
    memcpy(fields[count].data, packet + at, n);
    fields[count].data[n] = '\0';
    fields[count].size = n;
    at += n;
    count++;
  }
  return count;
}

static void error_text(int code, char *message, size_t size) {
  EricRueckgabepufferHandle buffer = eric.puffer_erzeugen();
  const char *text = "";
  if (buffer && eric.hole_fehler_text(code, buffer) == ERIC_OK) text = eric.puffer_inhalt(buffer);
  snprintf(message, size, "ERiC-Fehler %d: %s", code, text ? text : "");
  if (buffer) eric.puffer_freigeben(buffer);
}

static void elster_tax_number(field_t *fields, int count) {
  char message[1024];
  if (count != 3) {
    reply_error("stnr braucht Steuernummer und Landesnummer");
    return;
  }

  EricRueckgabepufferHandle buffer = eric.puffer_erzeugen();
  int code = eric.make_elster_stnr(fields[1].data, fields[2].data, NULL, buffer);
  if (code == ERIC_OK) {
    const char *number = eric.puffer_inhalt(buffer);
    reply("ok", 1, &number);
  } else {
    error_text(code, message, sizeof message);
    reply_error(message);
  }
  eric.puffer_freigeben(buffer);
}

static void send_return(field_t *fields, int count) {
  char message[1024];
  if (count != 6) {
    reply_error("send braucht XML, Datenart, Zertifikat, PIN und PDF");
    return;
  }

  EricZertifikatHandle certificate = 0;
  uint32_t pin_support = 0;
  int code = eric.get_handle_to_certificate(&certificate, &pin_support, fields[3].data);
  if (code != ERIC_OK) {
    error_text(code, message, sizeof message);
    reply_error(message);
    return;
  }

  eric_druck_parameter_t print = {4, 0, 0, fields[5].data, NULL, NULL, NULL};
  eric_verschluesselungs_parameter_t crypto = {3, certificate, fields[4].data};
  EricRueckgabepufferHandle answer = eric.puffer_erzeugen();
  EricRueckgabepufferHandle server = eric.puffer_erzeugen();

  code = eric.bearbeite_vorgang(fields[1].data, fields[2].data, ERIC_VALIDIERE | ERIC_SENDE | ERIC_DRUCKE, &print,
                                &crypto, answer, server);
  wipe(fields[4].data, fields[4].size);
  eric.close_handle_to_certificate(certificate);

  const char *server_answer = eric.puffer_inhalt(server);
  if (code == ERIC_OK) {
    reply("ok", 1, &server_answer);
  } else {
    error_text(code, message, sizeof message);
    const char *values[] = {message, eric.puffer_inhalt(answer), server_answer};
    reply("error", 3, values);
  }
  eric.puffer_freigeben(answer);
  eric.puffer_freigeben(server);
}

#define LOAD(field, name)                         \
  do {                                            \
    void *found = symbol(library, name);          \
    memcpy(&eric.field, &found, sizeof found);    \
  } while (0)

static void *symbol(void *library, const char *name) {
  void *found = dlsym(library, name);
  if (!found && !load_error[0]) snprintf(load_error, sizeof load_error, "ERiC hat kein %s", name);
  return found;
}

static int is_directory(const char *path) {
  struct stat info;
  return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

static void load(const char *home, const char *log_dir) {
  char path[4096];
  snprintf(path, sizeof path, "%s/lib/%s", home, ERIC_LIBRARY);
  void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    snprintf(load_error, sizeof load_error, "ERiC ließ sich nicht laden: %s", dlerror());
    return;
  }

  LOAD(initialisiere, "EricInitialisiere");
  LOAD(beende, "EricBeende");
  LOAD(puffer_erzeugen, "EricRueckgabepufferErzeugen");
  LOAD(puffer_inhalt, "EricRueckgabepufferInhalt");
  LOAD(puffer_freigeben, "EricRueckgabepufferFreigeben");
  LOAD(hole_fehler_text, "EricHoleFehlerText");
  LOAD(make_elster_stnr, "EricMakeElsterStnr");
  LOAD(get_handle_to_certificate, "EricGetHandleToCertificate");
  LOAD(close_handle_to_certificate, "EricCloseHandleToCertificate");
  LOAD(bearbeite_vorgang, "EricBearbeiteVorgang");
  if (load_error[0]) return;

  char plugins[4096];
  snprintf(plugins, sizeof plugins, "%s/lib/plugins", home);
  if (!is_directory(plugins)) snprintf(plugins, sizeof plugins, "%s/lib/plugins2", home);

  int code = eric.initialisiere(plugins, log_dir);
  if (code != ERIC_OK) snprintf(load_error, sizeof load_error, "ERiC ließ sich nicht starten: Fehler %d", code);
}

int main(int argc, char **argv) {
  /* ERiC must not write into the port's packets. */
  out_fd = dup(1);
  dup2(2, 1);

  if (argc != 3) {
    fprintf(stderr, "usage: elster <eric home> <log directory>\n");
    return 2;
  }
  load(argv[1], argv[2]);

  unsigned char header[4];
  while (read_exactly(header, 4) == 0) {
    uint32_t size = get_length(header);
    if (size > MAX_PACKET) return 1;
    unsigned char *packet = malloc(size ? size : 1);
    if (!packet || read_exactly(packet, size) != 0) return 1;

    field_t fields[MAX_FIELDS];
    int count = parse_fields(packet, size, fields);
    wipe(packet, size);
    free(packet);

    if (count < 1) {
      reply_error("unlesbare Anfrage");
    } else if (load_error[0]) {
      reply_error(load_error);
    } else if (strcmp(fields[0].data, "stnr") == 0) {
      elster_tax_number(fields, count);
    } else if (strcmp(fields[0].data, "send") == 0) {
      send_return(fields, count);
    } else {
      reply_error("unbekannter Befehl");
    }

    free_fields(fields, count);
  }

  if (!load_error[0]) eric.beende();
  return 0;
}
