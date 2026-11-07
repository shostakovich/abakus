/* A stand-in for ERiC's libericapi with the signatures of ERiC 44, for the tests of the ELSTER helper. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct {
  char *text;
} buffer_t;

typedef struct {
  uint32_t version, vorschau, duplexDruck;
  const char *pdfName;
  const char *fussText;
  void *pdfCallback;
  void *pdfCallbackBenutzerdaten;
} print_t;

typedef struct {
  uint32_t version;
  uint32_t zertifikatHandle;
  const char *pin;
} crypto_t;

static void put(buffer_t *buffer, const char *text) {
  free(buffer->text);
  buffer->text = strdup(text);
}

int EricInitialisiere(const char *plugins, const char *log) {
  (void)log;
  return strstr(plugins, "/lib/plugins") ? 0 : 610001001;
}

int EricBeende(void) { return 0; }

buffer_t *EricRueckgabepufferErzeugen(void) { return calloc(1, sizeof(buffer_t)); }

const char *EricRueckgabepufferInhalt(buffer_t *buffer) { return buffer->text ? buffer->text : ""; }

int EricRueckgabepufferFreigeben(buffer_t *buffer) {
  free(buffer->text);
  free(buffer);
  return 0;
}

int EricHoleFehlerText(int code, buffer_t *buffer) {
  char text[64];
  snprintf(text, sizeof text, "Fehlertext %d", code);
  put(buffer, text);
  return 0;
}

int EricMakeElsterStnr(const char *number, const char *state, const char *office, buffer_t *buffer) {
  if (office || strcmp(state, "11") != 0 || strcmp(number, "30/123/45678") != 0) return 610001034;
  put(buffer, "1130012345678");
  return 0;
}

int EricGetHandleToCertificate(uint32_t *handle, uint32_t *pin_support, const char *path) {
  char content[64] = {0};
  FILE *file = fopen(path, "rb");
  if (!file) return 610201016;
  fread(content, 1, sizeof content - 1, file);
  fclose(file);
  if (strcmp(content, "PKCS12 certificate") != 0) return 610201016;
  *handle = 7;
  *pin_support = 0;
  return 0;
}

int EricCloseHandleToCertificate(uint32_t handle) { return handle == 7 ? 0 : 610201017; }

int EricBearbeiteVorgang(const char *xml, const char *version, uint32_t flags, const print_t *print,
                         const crypto_t *crypto, buffer_t *answer, buffer_t *server) {
  if (flags != (2 | 4 | 32) || !print || print->version != 4 || !crypto || crypto->version != 3 ||
      crypto->zertifikatHandle != 7)
    return 610001002;
  if (strcmp(crypto->pin, "4711") != 0) return 610201101;
  if (strstr(xml, "CRASH")) abort();
  if (strncmp(xml, "HANG ", 5) == 0) {
    FILE *pid = fopen(xml + 5, "w");
    fprintf(pid, "%d", (int)getpid());
    fclose(pid);
    for (;;) pause();
  }
  if (strstr(xml, "FEHLER")) {
    put(answer, "<EricBearbeiteVorgang><FehlerRegelpruefung><Text>Die Kennzahl 83 fehlt.</Text>"
                "</FehlerRegelpruefung></EricBearbeiteVorgang>");
    return 610001222;
  }

  FILE *pdf = fopen(print->pdfName, "wb");
  fprintf(pdf, "%%PDF-mock %s %s", version, xml);
  fclose(pdf);
  put(server, "<Elster><TransferHeader><TransferTicket>tt-42</TransferTicket></TransferHeader></Elster>");
  return 0;
}
