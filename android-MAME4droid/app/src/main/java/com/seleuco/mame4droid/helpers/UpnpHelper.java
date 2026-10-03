/*
 * This file is part of MAME4droid.
 *
 * Copyright (C) 2026 David Valdeita (Seleuco)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses>.
 *
 * Linking MAME4droid statically or dynamically with other modules is
 * making a combined work based on MAME4droid. Thus, the terms and
 * conditions of the GNU General Public License cover the whole
 * combination.
 *
 * In addition, as a special exception, the copyright holders of MAME4droid
 * give you permission to combine MAME4droid with free software programs
 * or libraries that are released under the GNU LGPL and with code included
 * in the standard release of MAME under the MAME License (or modified
 * versions of such code, with unchanged license). You may copy and
 * distribute such a system following the terms of the GNU GPL for MAME4droid
 * and the licenses of the other code concerned, provided that you include
 * the source code of that other code when and as the GNU GPL requires
 * distribution of source code.
 *
 * Note that people who make modified versions of MAME4idroid are not
 * obligated to grant this special exception for their modified versions; it
 * is their choice whether to do so. The GNU General Public License
 * gives permission to release a modified version without this exception;
 * this exception also makes it possible to release a modified version
 * which carries forward this exception.
 *
 * MAME4droid is dual-licensed: Alternatively, you can license MAME4droid
 * under a MAME license, as set out in http://mamedev.org/
 */

package com.seleuco.mame4droid.helpers;

import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

/**
 * Minimal UPnP-IGD client: asks the router to forward the netplay UDP port
 * to this device (the automated version of the manual port-forward fallback,
 * which makes the host reachable even by symmetric-NAT/CGNAT peers).
 *
 * All methods block on network I/O: call ONLY from worker threads. HTTP runs
 * over raw sockets on purpose &mdash; Android's cleartext-HTTP policy blocks
 * HttpURLConnection to LAN addresses on modern targets, raw sockets it can't.
 */
public class UpnpHelper {

    private static final String TAG = "MAME4droid_Netplay";
    private static final String MAPPING_DESC = "MAME4droid NetPlay";

    /* WANPPPConnection matters: PPPoE fibre routers expose the WAN behind it. */
    private static final String[] WAN_SERVICES = {
            "urn:schemas-upnp-org:service:WANIPConnection:2",
            "urn:schemas-upnp-org:service:WANIPConnection:1",
            "urn:schemas-upnp-org:service:WANPPPConnection:1",
    };

    private static String sControlUrl = null;
    private static String sServiceType = null;
    private static int sExtPort = 0;
    private static boolean sMapped = false;

    public static synchronized boolean isMapped() {
        return sMapped;
    }

    /** Map external UDP <code>port</code> to this device's same port. */
    public static synchronized boolean addPortMapping(int port) {
        try {
            List<String> locations = discoverLocations(1500);
            if (locations.isEmpty()) {
                Log.d(TAG, "UPnP: no gateway found (SSDP timeout)");
                return false;
            }
            for (String location : locations) {
                String[] svc = findWanService(location);
                if (svc == null) continue;
                String serviceType = svc[0], controlUrl = svc[1];
                String internalIp = localIpToward(new URL(location).getHost());
                if (internalIp == null) continue;

                /* Permanent lease first (we delete it on disconnect; a killed
                 * app leaves a named stale entry the next create overwrites);
                 * some routers reject 0 and want a finite lease -> retry 2h. */
                int err = soapAddMapping(controlUrl, serviceType, port, internalIp, 0);
                if (err != 0)
                    err = soapAddMapping(controlUrl, serviceType, port, internalIp, 7200);
                if (err != 0) {
                    Log.d(TAG, "UPnP: AddPortMapping failed (error " + err + ") at " + controlUrl);
                    return false;
                }
                sControlUrl = controlUrl;
                sServiceType = serviceType;
                sExtPort = port;
                sMapped = true;
                Log.d(TAG, "UPnP: mapped UDP " + port + " -> " + internalIp + ":" + port
                        + " (" + serviceType + ")");
                verifyMapping(controlUrl, serviceType, port);
                return true;
            }
            Log.d(TAG, "UPnP: gateway found but no WAN*Connection service");
            return false;
        } catch (Throwable e) {
            Log.d(TAG, "UPnP: " + e);
            return false;
        }
    }

    /** Remove the mapping created by addPortMapping(); no-op if none. */
    public static synchronized void deletePortMapping() {
        if (!sMapped) return;
        try {
            String args = "<NewRemoteHost></NewRemoteHost>"
                    + "<NewExternalPort>" + sExtPort + "</NewExternalPort>"
                    + "<NewProtocol>UDP</NewProtocol>";
            int err = soapRequest(sControlUrl, sServiceType, "DeletePortMapping", args);
            Log.d(TAG, "UPnP: mapping for UDP " + sExtPort
                    + (err == 0 ? " removed" : " remove failed (error " + err + ")"));
        } catch (Throwable e) {
            Log.d(TAG, "UPnP: delete: " + e);
        }
        sMapped = false;
    }

    /* SSDP M-SEARCH for InternetGatewayDevice; replies are unicast so no
     * MulticastLock is needed. Returns the unique LOCATION urls seen. */
    private static List<String> discoverLocations(int timeoutMs) throws Exception {
        List<String> found = new ArrayList<String>();
        DatagramSocket sock = new DatagramSocket();
        try {
            sock.setSoTimeout(400);
            InetAddress group = InetAddress.getByName("239.255.255.250");
            /* The service ST cuts through non-IGD devices that (buggily)
             * answer every search: only real gateways reply to it. */
            String[] targets = {
                    "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
                    "urn:schemas-upnp-org:device:InternetGatewayDevice:2",
                    "urn:schemas-upnp-org:service:WANIPConnection:1",
            };
            for (String st : targets) {
                String ms = "M-SEARCH * HTTP/1.1\r\n"
                        + "HOST: 239.255.255.250:1900\r\n"
                        + "MAN: \"ssdp:discover\"\r\n"
                        + "MX: 1\r\n"
                        + "ST: " + st + "\r\n\r\n";
                byte[] b = ms.getBytes("US-ASCII");
                sock.send(new DatagramPacket(b, b.length, group, 1900));
            }
            long end = System.currentTimeMillis() + timeoutMs;
            byte[] buf = new byte[2048];
            while (System.currentTimeMillis() < end && found.size() < 8) {
                DatagramPacket p = new DatagramPacket(buf, buf.length);
                try {
                    sock.receive(p);
                } catch (SocketTimeoutException t) {
                    continue;
                }
                String rsp = new String(p.getData(), 0, p.getLength(), "US-ASCII");
                for (String line : rsp.split("\r\n")) {
                    int c = line.indexOf(':');
                    if (c > 0 && line.substring(0, c).trim().equalsIgnoreCase("LOCATION")) {
                        String loc = line.substring(c + 1).trim();
                        if (loc.length() > 0 && !found.contains(loc)) {
                            found.add(loc);
                            Log.d(TAG, "UPnP: SSDP location: " + loc
                                    + " (from " + p.getAddress().getHostAddress() + ")");
                        }
                    }
                }
            }
        } finally {
            sock.close();
        }
        return found;
    }

    /* Fetch the device description and return {serviceType, absoluteControlUrl}
     * of the first WAN*Connection service, or null. */
    private static String[] findWanService(String location) throws Exception {
        String rsp = httpExchange(location, null, null, 3000);
        if (rsp == null) {
            Log.d(TAG, "UPnP: no answer from " + location);
            return null;
        }
        String xml = bodyOf(rsp);
        if (xml == null) {
            Log.d(TAG, "UPnP: HTTP " + statusOf(rsp) + " from " + location);
            return null;
        }
        for (String st : WAN_SERVICES) {
            int i = xml.indexOf(st);
            while (i >= 0) {
                /* Namespace-tolerant: "controlURL>" matches <controlURL> and
                 * <ns:controlURL>; the 2KB window keeps the match inside this
                 * <service> block (spec order puts controlURL after the type). */
                int cu = xml.indexOf("controlURL>", i);
                if (cu >= 0 && cu < i + 2000) {
                    int vs = cu + "controlURL>".length();
                    int ve = xml.indexOf('<', vs);
                    if (ve > vs) {
                        String ctl = xml.substring(vs, ve).trim();
                        return new String[]{st, new URL(new URL(location), ctl).toString()};
                    }
                }
                i = xml.indexOf(st, i + 1);
            }
        }
        Log.d(TAG, "UPnP: no WAN service at " + location + " (igd="
                + (xml.contains("InternetGatewayDevice") ? "yes" : "no")
                + ", " + xml.length() + " bytes)");
        return null;
    }

    private static int soapAddMapping(String controlUrl, String serviceType,
                                      int port, String internalIp, int lease) throws Exception {
        String args = "<NewRemoteHost></NewRemoteHost>"
                + "<NewExternalPort>" + port + "</NewExternalPort>"
                + "<NewProtocol>UDP</NewProtocol>"
                + "<NewInternalPort>" + port + "</NewInternalPort>"
                + "<NewInternalClient>" + internalIp + "</NewInternalClient>"
                + "<NewEnabled>1</NewEnabled>"
                + "<NewPortMappingDescription>" + MAPPING_DESC + "</NewPortMappingDescription>"
                + "<NewLeaseDuration>" + lease + "</NewLeaseDuration>";
        return soapRequest(controlUrl, serviceType, "AddPortMapping", args);
    }

    /* One SOAP action; returns 0 on success, the UPnP <errorCode> (or the
     * HTTP status) on failure. */
    private static int soapRequest(String controlUrl, String serviceType,
                                   String action, String argsXml) throws Exception {
        String rsp = soapRaw(controlUrl, serviceType, action, argsXml);
        if (rsp == null) return -1;
        int code = statusOf(rsp);
        if (code == 200) return 0;
        int ec = errorCodeOf(rsp);
        return ec != 0 ? ec : code;
    }

    private static String soapRaw(String controlUrl, String serviceType,
                                  String action, String argsXml) throws Exception {
        String body = "<?xml version=\"1.0\"?>\r\n"
                + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
                + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body>"
                + "<u:" + action + " xmlns:u=\"" + serviceType + "\">" + argsXml
                + "</u:" + action + "></s:Body></s:Envelope>";
        return httpExchange(controlUrl, serviceType + "#" + action, body, 4000);
    }

    private static int errorCodeOf(String rsp) {
        int ec = rsp.indexOf("<errorCode>");
        if (ec >= 0) {
            int ee = rsp.indexOf("</errorCode>", ec);
            if (ee > ec) {
                try {
                    return Integer.parseInt(rsp.substring(ec + "<errorCode>".length(), ee).trim());
                } catch (NumberFormatException ignored) {
                }
            }
        }
        return 0;
    }

    private static String tagValue(String xml, String tag) {
        int i = xml.indexOf(tag + ">");
        if (i < 0) return "?";
        int vs = i + tag.length() + 1;
        int ve = xml.indexOf('<', vs);
        return ve > vs ? xml.substring(vs, ve).trim() : "?";
    }

    /* Read the mapping back from the router: some firmwares answer 200 to
     * AddPortMapping but never install the rule -- this exposes them. */
    private static void verifyMapping(String controlUrl, String serviceType, int port) {
        try {
            String args = "<NewRemoteHost></NewRemoteHost>"
                    + "<NewExternalPort>" + port + "</NewExternalPort>"
                    + "<NewProtocol>UDP</NewProtocol>";
            String rsp = soapRaw(controlUrl, serviceType, "GetSpecificPortMappingEntry", args);
            if (rsp == null) {
                Log.d(TAG, "UPnP: verify: no answer");
            } else if (statusOf(rsp) == 200) {
                Log.d(TAG, "UPnP: verify: router lists UDP " + port + " -> "
                        + tagValue(rsp, "NewInternalClient") + ":" + tagValue(rsp, "NewInternalPort")
                        + " enabled=" + tagValue(rsp, "NewEnabled")
                        + " lease=" + tagValue(rsp, "NewLeaseDuration"));
            } else {
                Log.d(TAG, "UPnP: verify: router does NOT list the mapping (HTTP "
                        + statusOf(rsp) + ", error " + errorCodeOf(rsp) + ")");
            }
        } catch (Throwable e) {
            Log.d(TAG, "UPnP: verify: " + e);
        }
    }

    /* HTTP/1.0 over a raw socket (no chunked replies, no cleartext policy).
     * GET when body == null, else SOAP POST. Returns headers+body, or null. */
    private static String httpExchange(String urlStr, String soapAction,
                                       String body, int timeoutMs) throws Exception {
        URL u = new URL(urlStr);
        int port = u.getPort() > 0 ? u.getPort() : 80;
        String path = u.getFile();
        if (path == null || path.length() == 0) path = "/";
        Socket s = new Socket();
        try {
            s.connect(new InetSocketAddress(u.getHost(), port), timeoutMs);
            s.setSoTimeout(timeoutMs);
            StringBuilder req = new StringBuilder();
            req.append(body == null ? "GET " : "POST ").append(path).append(" HTTP/1.0\r\n");
            req.append("Host: ").append(u.getHost()).append(':').append(port).append("\r\n");
            if (body != null) {
                byte[] bb = body.getBytes("UTF-8");
                req.append("Content-Type: text/xml; charset=\"utf-8\"\r\n");
                req.append("SOAPACTION: \"").append(soapAction).append("\"\r\n");
                req.append("Content-Length: ").append(bb.length).append("\r\n");
            }
            req.append("Connection: close\r\n\r\n");
            OutputStream os = s.getOutputStream();
            os.write(req.toString().getBytes("UTF-8"));
            if (body != null) os.write(body.getBytes("UTF-8"));
            os.flush();
            InputStream is = s.getInputStream();
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while (bo.size() < 262144 && (n = is.read(buf)) > 0) bo.write(buf, 0, n);
            return bo.size() > 0 ? bo.toString("UTF-8") : null;
        } finally {
            try {
                s.close();
            } catch (Exception ignored) {
            }
        }
    }

    private static int statusOf(String rsp) {
        try {
            int sp = rsp.indexOf(' ');
            return Integer.parseInt(rsp.substring(sp + 1, sp + 4));
        } catch (Exception e) {
            return -1;
        }
    }

    private static String bodyOf(String rsp) {
        if (rsp == null || statusOf(rsp) != 200) return null;
        int i = rsp.indexOf("\r\n\r\n");
        return i >= 0 ? rsp.substring(i + 4) : null;
    }

    /* The local IP the OS routes toward the gateway (a connected UDP socket
     * picks the source address without sending anything). */
    private static String localIpToward(String gatewayHost) {
        try {
            DatagramSocket s = new DatagramSocket();
            try {
                s.connect(InetAddress.getByName(gatewayHost), 9);
                InetAddress a = s.getLocalAddress();
                if (a != null && !a.isAnyLocalAddress()) return a.getHostAddress();
            } finally {
                s.close();
            }
        } catch (Exception ignored) {
        }
        return null;
    }
}
