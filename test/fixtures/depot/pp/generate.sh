#!/usr/bin/env bash
# Regenerates sample.portfolio with Portfolio Performance's own model and writer (needs Java 21).
# The PP bundles are downloaded to a temporary directory from PP's update site, never committed.
set -euo pipefail

PP_VERSION=0.88.0
SITE="https://updates.portfolio-performance.info/releases/${PP_VERSION}/plugins"
BUNDLES=(
  "name.abuchen.portfolio_${PP_VERSION}"
  com.google.protobuf_4.36.2
  com.google.gson_2.14.0
  com.google.guava_33.7.2.jre
  org.apache.servicemix.bundles.xstream_1.4.21.1
  org.apache.commons.commons-csv_1.14.1
  org.apache.commons.math3_3.6.1
  org.eclipse.osgi_3.24.200.v20260515-1403
  org.eclipse.equinox.common_3.20.400.v20260512-1534
  org.eclipse.core.runtime_3.34.200.v20251220-0953
  org.eclipse.core.jobs_3.15.800.v20260325-1353
  org.jsoup_1.23.2
  com.googlecode.json-simple_1.1.1
  org.apache.httpcomponents.client5.httpclient5_5.6.1.v20260420-1000
  org.apache.httpcomponents.core5.httpcore5_5.4.2.v20260306-1000
  wrapped.com.auth0.java-jwt_4.6.1
  org.osgi.service.component_1.5.1.202212101352
)

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for bundle in "${BUNDLES[@]}"; do
  curl -sSf -o "$tmp/$bundle.jar" "$SITE/$bundle.jar"
done

java -cp "$tmp/*" "$here/SampleFile.java" "$here/sample.portfolio"
