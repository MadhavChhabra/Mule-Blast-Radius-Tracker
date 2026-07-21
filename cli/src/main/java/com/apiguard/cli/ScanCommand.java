package com.apiguard.cli;

import com.apiguard.core.mule.MuleProjectScanner;
import com.apiguard.core.mule.MuleScan;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import picocli.CommandLine.Parameters;

import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.Callable;

@Command(name = "scan", mixinStandardHelpOptions = true,
        description = "Auto-discover downstream APIs from a Mule project (pom.xml + flow XML). No manifests needed.")
public final class ScanCommand implements Callable<Integer> {

    @Parameters(index = "0", paramLabel = "DIR",
            description = "A Mule project dir (containing pom.xml) or a folder of repos to scan.")
    Path dir;

    @Option(names = "--no-color", description = "Disable ANSI colour output.")
    boolean noColor;

    @Override
    public Integer call() {
        Ansi ansi = new Ansi(!noColor);
        List<MuleScan> scans = MuleProjectScanner.scanAll(dir);
        if (scans.isEmpty()) {
            System.out.println(ansi.yellow("No Mule projects found under " + dir));
            return 0;
        }
        for (MuleScan scan : scans) {
            printScan(ansi, scan);
        }
        return 0;
    }

    private void printScan(Ansi ansi, MuleScan scan) {
        System.out.println();
        System.out.println(ansi.bold(ansi.cyan("Mule app: " + scan.app()))
                + ansi.dim("   (" + scan.groupId() + ":" + scan.app() + ":" + scan.version() + ")"));

        System.out.println(ansi.bold("  Downstream APIs (overall):"));
        if (scan.downstreamApis().isEmpty()) {
            System.out.println("    " + ansi.dim("none discovered"));
        }
        for (String api : scan.downstreamApis()) {
            System.out.println("    - " + api);
        }

        System.out.println(ansi.bold("  Per endpoint:"));
        if (scan.endpoints().isEmpty()) {
            System.out.println("    " + ansi.dim("no APIkit endpoints found"));
        }
        for (MuleScan.InboundEndpoint ep : scan.endpoints()) {
            System.out.println("    " + ansi.cyan(ep.label()));
            if (ep.calls().isEmpty()) {
                System.out.println("        " + ansi.dim("(no downstream calls)"));
            }
            for (MuleScan.OutboundCall call : ep.calls()) {
                System.out.println("        -> " + String.format("%-22s", call.api())
                        + ansi.dim(call.endpoint()));
            }
        }
        if (!scan.orphanCalls().isEmpty()) {
            System.out.println(ansi.dim("  (plus " + scan.orphanCalls().size()
                    + " call(s) in shared sub-flows)"));
        }
    }
}
