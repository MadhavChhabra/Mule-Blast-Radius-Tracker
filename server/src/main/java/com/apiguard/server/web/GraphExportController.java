package com.apiguard.server.web;

import com.apiguard.server.service.GraphService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@RestController
@RequestMapping("/api/graph")
public class GraphExportController {

    private static final List<String> LAYER_ORDER =
            List.of("APP", "EXPERIENCE", "PROCESS", "SYSTEM", "BACKEND", "UNKNOWN");

    private final GraphService graphs;

    public GraphExportController(GraphService graphs) {
        this.graphs = graphs;
    }

    @GetMapping(value = "/export.csv", produces = "text/csv")
    public ResponseEntity<String> csv(@RequestParam(defaultValue = "nodes") String kind,
                                      @RequestParam(defaultValue = "false") boolean download) {
        Dtos.GraphDto g = graphs.build();
        String body = switch (kind.toLowerCase(Locale.ROOT)) {
            case "edges" -> edgesCsv(g);
            default -> nodesCsv(g);
        };
        String filename = "wakegraph-" + (kind.equalsIgnoreCase("edges") ? "edges" : "nodes") + ".csv";
        return withDownload(body, "text/csv; charset=utf-8", filename, download);
    }

    @GetMapping(value = "/export.svg", produces = "image/svg+xml")
    public ResponseEntity<String> svg(@RequestParam(defaultValue = "false") boolean download) {
        String body = renderSvg(graphs.build());
        return withDownload(body, "image/svg+xml; charset=utf-8", "wakegraph-estate.svg", download);
    }

    private static ResponseEntity<String> withDownload(String body, String contentType, String filename,
                                                       boolean download) {
        HttpHeaders headers = new HttpHeaders();
        headers.set(HttpHeaders.CONTENT_TYPE, contentType);
        if (download) {
            headers.set(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + filename + "\"");
        }
        return new ResponseEntity<>(body, headers, 200);
    }

    private static String nodesCsv(Dtos.GraphDto g) {
        StringBuilder sb = new StringBuilder("id,label,layer,api,depends_on,depended_on_by,owner_team,reviewers\n");
        for (Dtos.GraphNode n : g.nodes()) {
            append(sb, n.id());
            append(sb, n.label());
            append(sb, n.layer());
            append(sb, Boolean.toString(n.api()));
            append(sb, Integer.toString(n.dependsOn()));
            append(sb, Integer.toString(n.dependedOnBy()));
            append(sb, n.ownerTeam());
            append(sb, n.reviewers() == null ? "" : String.join("|", n.reviewers()));
            sb.setLength(sb.length() - 1);
            sb.append('\n');
        }
        return sb.toString();
    }

    private static String edgesCsv(Dtos.GraphDto g) {
        StringBuilder sb = new StringBuilder("from,to,label,risk,via\n");
        for (Dtos.GraphEdge e : g.edges()) {
            append(sb, e.from());
            append(sb, e.to());
            append(sb, e.label());
            append(sb, e.risk());
            append(sb, e.via() == null ? "" : String.join(" | ", e.via()));
            sb.setLength(sb.length() - 1);
            sb.append('\n');
        }
        return sb.toString();
    }

    private static void append(StringBuilder sb, String value) {
        String v = value == null ? "" : value;
        boolean needsQuote = v.indexOf(',') >= 0 || v.indexOf('"') >= 0 || v.indexOf('\n') >= 0;
        if (needsQuote) {
            sb.append('"').append(v.replace("\"", "\"\"")).append('"');
        } else {
            sb.append(v);
        }
        sb.append(',');
    }

    static String renderSvg(Dtos.GraphDto g) {
        Map<String, List<Dtos.GraphNode>> byLayer = new LinkedHashMap<>();
        for (String l : LAYER_ORDER) byLayer.put(l, new ArrayList<>());
        for (Dtos.GraphNode n : g.nodes()) {
            byLayer.computeIfAbsent(n.layer(), k -> new ArrayList<>()).add(n);
        }
        List<String> nonEmpty = new ArrayList<>();
        for (String l : byLayer.keySet()) {
            if (!byLayer.get(l).isEmpty()) nonEmpty.add(l);
        }

        int nodeW = 200, nodeH = 44, colGap = 60, rowGap = 16;
        int padX = 40, padY = 60;
        int maxRows = byLayer.values().stream().mapToInt(List::size).max().orElse(0);
        int width = padX * 2 + nonEmpty.size() * nodeW + Math.max(0, nonEmpty.size() - 1) * colGap;
        int height = padY * 2 + Math.max(maxRows, 1) * (nodeH + rowGap);

        Map<String, int[]> positions = new LinkedHashMap<>();
        for (int c = 0; c < nonEmpty.size(); c++) {
            String layer = nonEmpty.get(c);
            List<Dtos.GraphNode> col = byLayer.get(layer);
            int x = padX + c * (nodeW + colGap);
            for (int r = 0; r < col.size(); r++) {
                int y = padY + r * (nodeH + rowGap);
                positions.put(col.get(r).id(), new int[]{x, y});
            }
        }

        StringBuilder sb = new StringBuilder();
        sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 ")
          .append(width).append(' ').append(height).append("\" width=\"").append(width)
          .append("\" height=\"").append(height).append("\" font-family=\"system-ui,sans-serif\">\n");
        sb.append("<style>text{font-size:12px;fill:#222}"
                + ".layer{font-weight:700;font-size:11px;fill:#666;letter-spacing:.5px}"
                + ".node{fill:#fff;stroke:#3b5bdb;stroke-width:1.5}"
                + ".app{stroke:#7048e8}.experience{stroke:#e67700}.process{stroke:#2f9e44}"
                + ".system{stroke:#0b7285}.backend{stroke:#495057}.unknown{stroke:#adb5bd}"
                + ".edge{stroke:#adb5bd;stroke-width:1.2;fill:none}"
                + ".edge-breaking{stroke:#d6336c;stroke-width:2}"
                + ".edge-safe{stroke:#38b2ac}"
                + "</style>\n");

        for (int c = 0; c < nonEmpty.size(); c++) {
            String layer = nonEmpty.get(c);
            int x = padX + c * (nodeW + colGap);
            sb.append("<text class=\"layer\" x=\"").append(x).append("\" y=\"")
              .append(padY - 20).append("\">").append(escape(layer)).append("</text>\n");
        }

        for (Dtos.GraphEdge e : g.edges()) {
            int[] a = positions.get(e.from());
            int[] b = positions.get(e.to());
            if (a == null || b == null) continue;
            int x1 = a[0] + nodeW, y1 = a[1] + nodeH / 2;
            int x2 = b[0], y2 = b[1] + nodeH / 2;
            int midX = (x1 + x2) / 2;
            String cls = "edge";
            if ("breaking".equalsIgnoreCase(e.risk())) cls += " edge-breaking";
            else if ("safe".equalsIgnoreCase(e.risk())) cls += " edge-safe";
            sb.append("<path class=\"").append(cls).append("\" d=\"M")
              .append(x1).append(',').append(y1)
              .append(" C").append(midX).append(',').append(y1).append(' ')
              .append(midX).append(',').append(y2).append(' ')
              .append(x2).append(',').append(y2).append("\"/>\n");
        }

        for (Map.Entry<String, int[]> pos : positions.entrySet()) {
            Dtos.GraphNode node = g.nodes().stream().filter(n -> n.id().equals(pos.getKey()))
                    .findFirst().orElse(null);
            if (node == null) continue;
            int x = pos.getValue()[0], y = pos.getValue()[1];
            String layerClass = node.layer() == null ? "unknown" : node.layer().toLowerCase(Locale.ROOT);
            sb.append("<rect class=\"node ").append(layerClass).append("\" x=\"").append(x)
              .append("\" y=\"").append(y).append("\" width=\"").append(nodeW)
              .append("\" height=\"").append(nodeH).append("\" rx=\"8\"/>\n");
            sb.append("<text x=\"").append(x + 12).append("\" y=\"").append(y + 20).append("\">")
              .append(escape(node.label())).append("</text>\n");
            sb.append("<text x=\"").append(x + 12).append("\" y=\"").append(y + 34)
              .append("\" font-size=\"10\" fill=\"#666\">").append(node.dependsOn()).append(" out · ")
              .append(node.dependedOnBy()).append(" in</text>\n");
        }

        sb.append("</svg>\n");
        return sb.toString();
    }

    private static String escape(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;");
    }
}
