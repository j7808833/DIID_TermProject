import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/home_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _ipController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    final provider = Provider.of<HomeProvider>(context, listen: false);
    _ipController.text = provider.serverIp;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Consumer<HomeProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text("Trigger Sensitivity (Threshold)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("${provider.sensitivity.toStringAsFixed(1)} G",
                  style: const TextStyle(fontSize: 24, color: Colors.blue)),
              Slider(
                value: provider.sensitivity,
                min: 1.1,
                max: 5.0,
                divisions: 39,
                label: provider.sensitivity.toStringAsFixed(1),
                onChanged: (value) {
                  provider.updateSettings(value, provider.serverIp);
                },
              ),
              const Text("Lower = More Sensitive (Easier to trigger)"),
              const Divider(height: 32),
              
              const Text("Server IP Address",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "e.g. 192.168.0.100",
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (value) {
                  provider.updateSettings(provider.sensitivity, value);
                },
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                    provider.updateSettings(provider.sensitivity, _ipController.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("IP Saved & Reconnecting..."))
                    );
                }, 
                child: const Text("Save & Reconnect")
              ),
              
              const Divider(height: 32),
              
              const Text("Sensor Calibration",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("Place the racket flat on the ground before calibrating.",
                   style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 16),
              Center(
                child: provider.isCalibrating
                    ? const Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text("Calibrating... Do not move the racket."),
                        ],
                      )
                    : ElevatedButton.icon(
                        onPressed: () {
                          provider.startCalibration();
                        },
                        icon: const Icon(Icons.build),
                        label: const Text("Start Zero Calibration"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                      ),
              ),
              if (provider.isCalibrated)
                  Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text("Calibration Active\nOffsets: Acc(${provider.accOffset[0].toStringAsFixed(2)}, ${provider.accOffset[1].toStringAsFixed(2)}, ${provider.accOffset[2].toStringAsFixed(2)})",
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.green)),
                  ),
            ],
          );
        },
      ),
    );
  }
}
