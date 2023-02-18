import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_settings/open_settings.dart';
import 'package:siemens_wifi_app/WifiConnect.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WiFi Settings',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // home: FlutterWifiIoT(),
      home: const MyHomePage(title: 'Siemens WiFi Settings'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  int _counter = 0;
  String? connectedSSID = '';
  bool _switchValue = false;
  bool connected = false;

  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkIfWiFiEnabled();

    initConnectivity();

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    super.dispose();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initConnectivity() async {
    late ConnectivityResult result;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      result = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      print('Couldn\'t check connectivity status == ${e}');
      return;
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) {
      return Future.value(null);
    }

    return _updateConnectionStatus(result);
  }

  bool iosWifiConnected = false;
  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    setState(() {
      _connectionStatus = result;
      if (_connectionStatus == ConnectivityResult.none) {
        connected = false;
      }
    });
    if (_connectionStatus == ConnectivityResult.wifi) {
      setState(() {
        iosWifiConnected = true;
        _switchValue = true;
        connected = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkIfWiFiEnabled();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Stack(children: [
        Column(children: [
          ListTile(
            title: Text("WiFi"),
            trailing: CupertinoSwitch(
              value: _switchValue,
              onChanged: (value) async {
                print(value);
                if (Platform.isAndroid) {
                  await WiFiForIoTPlugin.setEnabled(true,
                      shouldOpenSettings: true);
                } else {
                  // AppSettings.openWIFISettings();
                  OpenSettings.openWIFISetting();
                }
              },
            ),
          ),
          Platform.isIOS
              ? iosWifiConnected
                  ? Center(child: Text("Connected to WiFi"))
                  : Center(child: Text("Not Connected to WiFi"))
              : Container(),
          Platform.isAndroid
              ? loading
                  ? CircularProgressIndicator()
                  : !_switchValue
                      ? Center(
                          child: Text("Turn on wifi to check nearby networks"))
                      : accessPoints.length == 0
                          ? Center(child: Text("Scan to get nearby networks."))
                          : wifiList()
              : Container()
        ]),
        Positioned(
            bottom: 15,
            left: 120,
            child: Center(
              child: connected
                  ? Image.network(
                      'https://i.pinimg.com/564x/d7/c9/51/d7c951b1dc5bc980942508e3f9328923.jpg',
                      height: 100,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(child: Text("No internet..!!!🙁"));
                      },
                    )
                  : Text("No internet..!!🙁"),
            ))
      ]),
      floatingActionButton: FloatingActionButton(
          onPressed: () {
            _startListeningToScannedResults();
          },
          child: Text("Scan")),
    );
  }

  Widget wifiList() {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: accessPoints.length,
      itemBuilder: (context, index) {
        int strengthRank = getSignalStrength(accessPoints[index].level);
        if (accessPoints[index].ssid != '') {
          return ListTile(
            shape: const RoundedRectangleBorder(
                side: BorderSide(
                    color: Color.fromARGB(255, 221, 221, 221), width: 0)),
            trailing: connectedSSID == accessPoints[index].ssid
                ? const Icon(
                    Icons.check,
                    color: Colors.green,
                  )
                : accessPoints[index].capabilities.contains('WPA') ||
                        accessPoints[index].capabilities.contains('WPA2')
                    ? Icon(
                        Icons.lock,
                        color: Colors.grey,
                      )
                    : Container(),
            title: Text('${accessPoints[index].ssid}'),
            leading: strengthRank == 1
                ? Icon(Icons.wifi)
                : strengthRank == 2
                    ? Icon(Icons.wifi_2_bar_sharp)
                    : Icon(Icons.wifi_1_bar_sharp),
            onTap: () async {
              selectedSSID = accessPoints[index].ssid;
              if (connectedSSID == selectedSSID) {
                disconnect();
              } else {
                enterPassword();
              }
            },
          );
        } else {
          return Container();
        }
      },
    );
  }

  int getSignalStrength(int inDBs) {
    if (inDBs > -67) {
      return 1;
    } else if (inDBs < -68 && inDBs > -80) {
      return 2;
    } else {
      return 3;
    }
  }

  disconnect() async {
    bool disconnected = await WiFiForIoTPlugin.disconnect();
    if (disconnected) {
      var snackBar = SnackBar(
        content: Text('Disconnected from ${connectedSSID}'),
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      setState(() {
        connectedSSID = '';
        connected = false;
      });
    } else {
      var snackBar = SnackBar(
        content: Text('Unable to Disconnect from ${connectedSSID}'),
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

//Popup to enter password for selected network
  String selectedSSID = '';
  String password = '';
  enterPassword() {
    showModalBottomSheet(
        isDismissible: false,
        isScrollControlled: true,
        context: context,
        builder: (BuildContext context) {
          return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                  height: 200,
                  padding: EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text("Enter Password"),
                      const Divider(thickness: 1),
                      TextField(
                        onChanged: (value) {
                          password = value;
                        },
                        autofocus: true,
                        decoration: InputDecoration(
                            helperText: 'Enter Password',
                            filled: true,
                            errorText: _errText == '' ? null : _errText,
                            fillColor: Color.fromARGB(255, 255, 255, 255)),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                              onPressed: () => {Navigator.pop(context)},
                              child: const Text("Cancel")),
                          ElevatedButton(
                              style: ButtonStyle(
                                  backgroundColor: MaterialStateProperty.all(
                                      Colors.deepPurple)),
                              onPressed: () {
                                connectToWiFi();
                              },
                              child: const Text(
                                "Connect",
                                style: TextStyle(color: Colors.white),
                              ))
                        ],
                      )
                    ],
                  )));
        });
  }

  // initialize accessPoints and subscription
  List<WiFiAccessPoint> accessPoints = [];
  StreamSubscription<List<WiFiAccessPoint>>? subscription;
  bool loading = false;
  String _errText = '';
  void _startListeningToScannedResults() async {
    // check platform support and necessary requirements
    if (accessPoints.isEmpty) {
      setState(() {
        loading = true;
      });
    }
    final can =
        await WiFiScan.instance.canGetScannedResults(askPermissions: true);
    switch (can) {
      case CanGetScannedResults.yes:

        // listen to onScannedResultsAvailable stream
        subscription =
            WiFiScan.instance.onScannedResultsAvailable.listen((results) {
          // update accessPoints
          setState(() {
            loading = false;
            accessPoints = results;
          });
        });

        break;
      //case CanGetScannedResults.notSupported
      case CanGetScannedResults.notSupported:
        print("Not supported");
        setState(() {
          loading = false;
        });
        // TODO: Handle this case.
        break;
      case CanGetScannedResults.noLocationPermissionRequired:
        // TODO: Handle this case.
        break;
      case CanGetScannedResults.noLocationPermissionDenied:
        // TODO: Handle this case.
        break;
      case CanGetScannedResults.noLocationPermissionUpgradeAccuracy:
        // TODO: Handle this case.
        break;
      case CanGetScannedResults.noLocationServiceDisabled:

        // TODO: Handle this case.
        break;
    }
  }

  checkIfWiFiEnabled() {
    if (Platform.isAndroid) {
      WiFiForIoTPlugin.isEnabled().then((val) {
        setState(() {
          _switchValue = val;
        });
        if (val) checkIfWiFiIsConnected();
        if (!val) {
          setState(() {
            connected = false;
            connectedSSID = '';
          });
        }
      });
    } else {
      if (iosWifiConnected) {
        setState(() {
          connected = true;
        });
      }
    }
  }

  checkIfWiFiIsConnected() {
    WiFiForIoTPlugin.isConnected().then((val) {
      setState(() {
        connected = val;
      });
      if (val) getConnectedSSID();
    });
  }

  getConnectedSSID() async {
    connectedSSID = await WiFiForIoTPlugin.getSSID();
    _startListeningToScannedResults();
    setState(() {
      connectedSSID = connectedSSID;
    });
  }

  // loadContent() async {
  //   int? strength = await WiFiForIoTPlugin.getCurrentSignalStrength();
  //   print(strength);
  // }

  connectToWiFi() async {
    bool connected1 = await WiFiForIoTPlugin.connect(selectedSSID,
        password: password, security: NetworkSecurity.WPA, withInternet: true);
    if (connected1) {
      if (!mounted) return;
      Navigator.pop(context);
      await getConnectedSSID();
      setState(() {
        connected = true;
        _errText = '';
      });
    } else {
      setState(() {
        _errText = 'Wrong Password';
      });
    }
  }
}
