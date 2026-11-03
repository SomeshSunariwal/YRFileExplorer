package com.somesh.yrfileexplorer.network;

import android.Manifest;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.*;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.*;

public final class NetworkEnvironment {
    public static Map<String,Object> info(Context context){
        ConnectivityManager manager=context.getSystemService(ConnectivityManager.class);Network network=manager.getActiveNetwork();NetworkCapabilities capabilities=network==null?null:manager.getNetworkCapabilities(network);LinkProperties properties=network==null?null:manager.getLinkProperties(network);
        String kind=capabilities==null?"Disconnected":capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)?"Wi-Fi":capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)?"Ethernet":capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)?"Mobile network":"Network";
        List<String> addresses=new ArrayList<>(),dns=new ArrayList<>(),gateways=new ArrayList<>();String iface="";int mtu=0;
        if(properties!=null){iface=properties.getInterfaceName()==null?"":properties.getInterfaceName();mtu=properties.getMtu();for(LinkAddress address:properties.getLinkAddresses())addresses.add(address.toString());for(InetAddress address:properties.getDnsServers())dns.add(address.getHostAddress());for(RouteInfo route:properties.getRoutes())if(route.isDefaultRoute()&&route.getGateway()!=null)gateways.add(route.getGateway().getHostAddress());}
        return Map.of("type",kind,"connected",network!=null,"addresses",addresses,"dns",dns,"gateways",gateways,"interface",iface,"mtu",mtu,"metered",network!=null&&manager.isActiveNetworkMetered());
    }

    public static List<Map<String,Object>> scan(Context context, java.util.concurrent.atomic.AtomicBoolean cancelled)throws Exception {
        ConnectivityManager manager=context.getSystemService(ConnectivityManager.class);Network network=manager.getActiveNetwork();LinkProperties properties=network==null?null:manager.getLinkProperties(network);
        if(properties==null)throw new IOException("Connect to a local Wi-Fi or Ethernet network first");
        Inet4Address local=null;int prefixLength=24;
        for(LinkAddress address:properties.getLinkAddresses())if(address.getAddress() instanceof Inet4Address ipv4 && ipv4.isSiteLocalAddress()){local=ipv4;prefixLength=Math.max(24,address.getPrefixLength());break;}
        if(local==null)throw new IOException("No private IPv4 network is available");
        byte[] prefix=local.getAddress();String base=(prefix[0]&255)+"."+(prefix[1]&255)+"."+(prefix[2]&255)+".";
        int hostMask=prefixLength>=31?0:((1<<(32-prefixLength))-1);
        int first=((prefix[3]&255)&~hostMask)+1,last=((prefix[3]&255)|hostMask);
        ExecutorService workers=Executors.newFixedThreadPool(24);List<Future<Map<String,Object>>> jobs=new ArrayList<>();
        try{
            for(int host=first;host<last;host++){if(cancelled.get())break;if(host==(prefix[3]&255))continue;String ip=base+host;jobs.add(workers.submit(()->{try(Socket socket=new Socket()){if(cancelled.get())return null;socket.connect(new InetSocketAddress(ip,445),300);return Map.<String,Object>of("host",ip,"name",ip,"port","445","protocol","SMB");}catch(IOException ignored){return null;}}));}
            List<Map<String,Object>> found=new ArrayList<>();for(Future<Map<String,Object>> job:jobs){if(cancelled.get())break;Map<String,Object> device=job.get();if(device!=null)found.add(device);}return found;
        }finally{workers.shutdownNow();}
    }
    public static BluetoothAdapter adapter(Context context){BluetoothManager manager=context.getSystemService(BluetoothManager.class);return manager==null?null:manager.getAdapter();}
    public static boolean bluetoothAllowed(Context context){return context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)==PackageManager.PERMISSION_GRANTED;}
    public static Map<String,Object> device(BluetoothDevice device){Map<String,Object> row=new HashMap<>();String name=device.getName();row.put("name",name==null?device.getAddress():name);row.put("address",device.getAddress());row.put("bonded",device.getBondState()==BluetoothDevice.BOND_BONDED);List<String> uuids=new ArrayList<>();if(device.getUuids()!=null)for(android.os.ParcelUuid uuid:device.getUuids())uuids.add(uuid.toString());row.put("uuids",uuids);return row;}
    public static Map<String,Object> bluetooth(Context context){
        BluetoothAdapter adapter=adapter(context);boolean allowed=bluetoothAllowed(context);List<Map<String,Object>> devices=new ArrayList<>();
        if(adapter!=null&&allowed)for(BluetoothDevice device:adapter.getBondedDevices())devices.add(device(device));
        return Map.of("supported",adapter!=null,"permission",allowed,"scanPermission",context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED,"enabled",adapter!=null&&allowed&&adapter.isEnabled(),"devices",devices);
    }
}
