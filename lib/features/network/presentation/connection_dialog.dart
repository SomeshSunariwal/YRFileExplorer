import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';

class ConnectionDialog extends StatefulWidget {
  final Json? profile;
  const ConnectionDialog({super.key, this.profile});
  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late String protocol, encoding;
  bool rememberPassword = false, implicit = false;
  bool save = true, anonymous = false, passive = true, showPassword = false;
  @override
  void initState() {
    super.initState();
    protocol = widget.profile?['protocol'] ?? 'SFTP';
    encoding = widget.profile?['encoding'] ?? 'AUTO';
    anonymous = widget.profile?['anonymous'] == true;
    implicit = widget.profile?['implicit'] == true;
    rememberPassword = widget.profile?['rememberPassword'] == true;
    passive = widget.profile?['passive'] != false;
    for (final key in [
      'name',
      'host',
      'port',
      'username',
      'password',
      'path',
      'domain',
      'share',
    ]) {
      fields[key] = TextEditingController(
        text:
            widget.profile?[key]?.toString() ??
            (key == 'path'
                ? '/'
                : key == 'port'
                ? (protocol == 'SMB'
                      ? '445'
                      : protocol == 'SFTP'
                      ? '22'
                      : protocol == 'FTPS' && implicit
                      ? '990'
                      : protocol == 'WebDAV'
                      ? '443'
                      : '21')
                : ''),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget row(String label, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child:
        control is TextFormField || control is DropdownButtonFormField<String>
        ? control
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              control,
            ],
          ),
  );
  Widget field(String key, String hint, {bool secret = false}) => TextFormField(
    controller: fields[key],
    enabled: !anonymous || !['username', 'password'].contains(key),
    obscureText: secret && !showPassword,
    autocorrect: false,
    enableSuggestions: !secret,
    keyboardType: key == 'port' ? TextInputType.number : TextInputType.text,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      labelText: const {
        'host': 'Server',
        'port': 'Port',
        'domain': 'Domain',
        'share': 'Share',
        'username': 'Username',
        'password': 'Password',
        'name': 'Display as',
        'path': 'Path',
      }[key],
      hintText: hint,
      suffixIcon: secret
          ? IconButton(
              tooltip: showPassword ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => showPassword = !showPassword),
              icon: Icon(
                showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
            )
          : null,
    ),
    validator: (value) {
      if (key == 'host') {
        final address = value?.trim() ?? '';
        if (address.isEmpty) return 'Enter server';
        if (protocol == 'WebDAV') {
          final uri = Uri.tryParse(
            address.contains('://') ? address : 'https://$address',
          );
          if (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            return 'Enter an HTTP or HTTPS server URL';
          }
        } else if (address.contains('/') ||
            address.contains('://') ||
            address.contains(' ')) {
          return 'Enter a hostname or IP address';
        }
      }
      if (key == 'port') {
        final p = int.tryParse(value ?? '');
        if (p == null || p < 1 || p > 65535) return 'Use 1–65535';
      }
      if (key == 'username' &&
          protocol != 'WebDAV' &&
          !anonymous &&
          (value == null || value.trim().isEmpty)) {
        return 'Enter username';
      }
      return null;
    },
  );
  @override
  Widget build(BuildContext context) => ExplorerDialog(
    title: Text(
      '${widget.profile?['host'] == null ? 'New' : 'Edit'} $protocol Server',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 360,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row('Server', field('host', '$protocol host server')),
              if (protocol != 'WebDAV')
                row(
                  'Port',
                  field(
                    'port',
                    protocol == 'SMB'
                        ? '445'
                        : protocol == 'SFTP'
                        ? '22'
                        : '21',
                  ),
                ),
              if (['FTP', 'FTPS'].contains(protocol))
                row(
                  'Mode',
                  SegmentedButton<bool>(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Active', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Passive', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {passive},
                    onSelectionChanged: (v) =>
                        setState(() => passive = v.first),
                  ),
                ),
              if (protocol == 'SMB')
                row('Domain', field('domain', 'Optional domain')),
              if (protocol == 'SMB')
                row('Share', field('share', 'Optional — browse shares')),
              row('Username', field('username', 'Username')),
              row('Password', field('password', 'Password', secret: true)),
              if (protocol == 'FTPS')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Implicit TLS',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Port 990; otherwise explicit TLS on port 21',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: implicit,
                  onChanged: (value) => setState(() {
                    implicit = value;
                    fields['port']!.text = value ? '990' : '21';
                  }),
                ),
              if (['FTP', 'FTPS', 'SMB'].contains(protocol))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    protocol == 'SMB' ? 'Guest access' : 'Anonymous',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: anonymous,
                  onChanged: (v) => setState(() => anonymous = v!),
                ),
              if (!['SMB', 'WebDAV'].contains(protocol))
                row(
                  'Encoding',
                  DropdownButtonFormField<String>(
                    initialValue: encoding,
                    elevation: Theme.of(context).brightness == Brightness.dark
                        ? 0
                        : 8,
                    isExpanded: true,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: [
                      for (final name in [
                        'AUTO',
                        'UTF-8',
                        'GBK',
                        'Big5',
                        'Shift_JIS',
                        'ISO-8859-1',
                      ])
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: (v) => setState(() => encoding = v!),
                    decoration: const InputDecoration(labelText: 'Encoding'),
                  ),
                ),
              row('Display as', field('name', 'Optional name')),
              row('Path', field('path', '/')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Remember password',
                  style: TextStyle(fontSize: 13),
                ),
                value: rememberPassword,
                onChanged: (value) => setState(() => rememberPassword = value!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Save connection',
                  style: TextStyle(fontSize: 13),
                ),
                value: save,
                onChanged: (v) => setState(() => save = v!),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, <String, dynamic>{
            ...?widget.profile,
            for (final e in fields.entries)
              e.key: e.key == 'password' ? e.value.text : e.value.text.trim(),
            'protocol': protocol,
            'encoding': encoding,
            'passive': passive,
            'implicit': implicit,
            'anonymous': anonymous,
            'username': anonymous
                ? (protocol == 'SMB' ? '' : 'anonymous')
                : fields['username']!.text.trim(),
            'password': anonymous
                ? (protocol == 'SMB' ? '' : 'anonymous@')
                : fields['password']!.text,
            'save': save,
            'rememberPassword': rememberPassword && save,
            'name': fields['name']!.text.trim().isEmpty
                ? fields['host']!.text.trim()
                : fields['name']!.text.trim(),
          });
        },
        child: const Text('OK'),
      ),
    ],
  );
}
