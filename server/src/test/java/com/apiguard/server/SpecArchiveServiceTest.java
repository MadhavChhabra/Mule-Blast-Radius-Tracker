package com.apiguard.server;

import com.apiguard.server.service.SpecArchiveService;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SpecArchiveServiceTest {

    private static byte[] zip(Map<String, String> files) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (ZipOutputStream zos = new ZipOutputStream(bos)) {
            for (var e : files.entrySet()) {
                zos.putNextEntry(new ZipEntry(e.getKey()));
                zos.write(e.getValue().getBytes(StandardCharsets.UTF_8));
                zos.closeEntry();
            }
        }
        return bos.toByteArray();
    }

    @Test
    void extractsRamlAssetWithIncludesIntoOpenApi() throws IOException {

        String apiRaml = """
                #%RAML 1.0
                title: Orders API
                version: v1
                types:
                  Order: !include types/order.raml
                /orders/{orderId}:
                  uriParameters:
                    orderId: string
                  get:
                    responses:
                      200:
                        body:
                          application/json:
                            type: Order
                """;
        String orderType = """
                #%RAML 1.0 DataType
                type: object
                properties:
                  orderId: string
                  customerId: string
                  status:
                    type: string
                    enum: [open, paid, closed]
                """;
        byte[] zip = zip(Map.of(
                "exchange.json", "{\"main\": \"api.raml\", \"name\": \"orders-api\"}",
                "api.raml", apiRaml,
                "types/order.raml", orderType));

        SpecArchiveService service = new SpecArchiveService();
        SpecArchiveService.ExtractedSpec extracted = service.fromZip(new ByteArrayInputStream(zip));

        assertTrue(extracted.spec().contains("/orders/{orderId}"), extracted.spec());
        assertTrue(extracted.spec().contains("customerId"),
                () -> "the !include'd type's fields should be inlined:\n" + extracted.spec());
        assertTrue(extracted.title().contains("Orders"), extracted.title());
    }

    @Test
    void refusesAnArchiveThatExpandsPastTheSizeCap() throws IOException {
        // ~1 KB of zeroes compresses to almost nothing but expands past the cap when repeated:
        // the classic zip bomb the extractor must refuse rather than write to disk.
        String chunk = "0".repeat(1024 * 1024);
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (ZipOutputStream zos = new ZipOutputStream(bos)) {
            for (int i = 0; i < 128; i++) {
                zos.putNextEntry(new ZipEntry("pad/" + i + ".txt"));
                zos.write(chunk.getBytes(StandardCharsets.UTF_8));
                zos.closeEntry();
            }
        }

        SpecArchiveService service = new SpecArchiveService();
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class,
                () -> service.fromZip(new ByteArrayInputStream(bos.toByteArray())));
        assertTrue(e.getMessage().contains("MB"), e.getMessage());
    }

    @Test
    void refusesAnArchiveWithTooManyEntries() throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        try (ZipOutputStream zos = new ZipOutputStream(bos)) {
            for (int i = 0; i <= SpecArchiveService.MAX_ENTRIES; i++) {
                zos.putNextEntry(new ZipEntry("f" + i + ".txt"));
                zos.write('x');
                zos.closeEntry();
            }
        }

        SpecArchiveService service = new SpecArchiveService();
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class,
                () -> service.fromZip(new ByteArrayInputStream(bos.toByteArray())));
        assertTrue(e.getMessage().contains("entries"), e.getMessage());
    }
}
