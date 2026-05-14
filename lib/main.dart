import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'oficina/modulo_oficina.dart';
import 'pos/modulo_pos.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SaasApp());
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class SaasApp extends StatelessWidget {
  const SaasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS SaaS',
      debugShowCheckedModeBanner: false,
      scrollBehavior: AppScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          primary: Colors.black,
          surface: const Color(0xFFF6F8FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            side: const BorderSide(color: Colors.black12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 🚨 NUEVO CAMPO: Código de Empresa (Multi-Tenant)
  final TextEditingController _empresaController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  bool _isLoading = false;
  bool _isBiometricLoading = false;
  final LocalAuthentication _auth = LocalAuthentication();

  bool _mostrarBotonBiometrico = false;
  String _usuarioGuardado = '';
  String _labelBiometrico = 'BIOMETRÍA';
  IconData _iconoBiometrico = Icons.fingerprint;

  @override
  void initState() {
    super.initState();
    _verificarPerfilGuardado();
  }

  Future<void> _verificarPerfilGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    final String? perfil = prefs.getString('perfil_usuario');
    final String? usuario = prefs.getString('usuario_guardado');
    // Para biometría, debes asegurarte que también existe el token JWT
    final String? token = prefs.getString('token_jwt');

    if (perfil != null && usuario != null && token != null) {
      bool canCheckBiometrics = await _auth.canCheckBiometrics;
      bool isDeviceSupported = await _auth.isDeviceSupported();

      if (canCheckBiometrics && isDeviceSupported) {
        List<BiometricType> biometrics = await _auth.getAvailableBiometrics();
        String tipoBio = 'BIOMETRÍA';
        IconData iconoBio = Icons.security;

        if (biometrics.contains(BiometricType.face)) {
          tipoBio = 'FACE ID';
          iconoBio = Icons.face_unlock_outlined;
        } else if (biometrics.contains(BiometricType.fingerprint)) {
          tipoBio = 'HUELLA';
          iconoBio = Icons.fingerprint;
        } else if (biometrics.contains(BiometricType.strong) ||
            biometrics.contains(BiometricType.weak)) {
          tipoBio = 'HUELLA / ROSTRO';
          iconoBio = Icons.fingerprint;
        }

        if (!mounted) return;
        setState(() {
          _mostrarBotonBiometrico = true;
          _usuarioGuardado = usuario;
          _labelBiometrico = tipoBio;
          _iconoBiometrico = iconoBio;
        });
      }
    }
  }

  Future<void> _login() async {
    final empresa = _empresaController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (empresa.isEmpty || user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa código de empresa, usuario y contraseña'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Petición para Oficina
      var resOficina = await http.post(
        Uri.parse('${ApiService.baseUrl}/oficina/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "codigo_empresa": empresa,
          "usuario": user,
          "password": pass,
        }),
      );

      if (!mounted) return;

      if (resOficina.statusCode == 200) {
        final data = jsonDecode(resOficina.body);
        await prefs.setString('perfil_usuario', 'oficina');
        await prefs.setString('usuario_guardado', user);
        // 🚨 SE GUARDA EL TOKEN JWT Y LA EMPRESA
        await prefs.setString('token_jwt', data['token']);
        await prefs.setString('codigo_empresa', empresa);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CentroDeControlAdmin()),
        );
        return;
      }

      // Petición para POS
      var resCajero = await http.post(
        Uri.parse('${ApiService.baseUrl}/pos/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "codigo_empresa": empresa,
          "usuario": user,
          "password": pass,
        }),
      );

      if (!mounted) return;

      if (resCajero.statusCode == 200) {
        final data = jsonDecode(resCajero.body);
        await prefs.setString('perfil_usuario', 'cajero');
        await prefs.setString('usuario_guardado', user);
        // 🚨 SE GUARDA EL TOKEN JWT Y LA EMPRESA
        await prefs.setString('token_jwt', data['token']);
        await prefs.setString('codigo_empresa', empresa);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MostradorCajero()),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Credenciales incorrectas o empresa suspendida'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error de conexión con el servidor'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _iniciarConBiometria() async {
    setState(() => _isBiometricLoading = true);

    try {
      bool exito = await _auth.authenticate(
        localizedReason:
            'Verifica tu identidad para entrar como ${_usuarioGuardado.toUpperCase()}',
      );

      if (!mounted) return;

      if (exito) {
        final prefs = await SharedPreferences.getInstance();
        final String? perfil = prefs.getString('perfil_usuario');

        if (!mounted) return;

        if (perfil == 'oficina') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CentroDeControlAdmin()),
          );
        } else if (perfil == 'cajero') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MostradorCajero()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Perfil no encontrado. Inicia sesión con contraseña la primera vez.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } on PlatformException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de hardware. Inicia sesión con contraseña.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBiometricLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0x0D000000)),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 24,
                    spreadRadius: 8,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    width: 90,
                    height: 90,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.storefront,
                        size: 60,
                        color: Colors.black54,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PUNTO DE VENTA',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2,
                    ),
                  ),
                  const Text(
                    'INICIO DE SESIÓN',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // 🚨 NUEVO CAMPO: Código de Empresa
                  TextField(
                    controller: _empresaController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Código de Empresa',
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _userController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'ACCEDER AL SISTEMA',
                              style: TextStyle(
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_mostrarBotonBiometrico) ...[
                    Text(
                      'Continuar como: ${_usuarioGuardado.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(
                            color: Colors.black26,
                            width: 1.5,
                          ),
                        ),
                        onPressed: _isBiometricLoading
                            ? null
                            : _iniciarConBiometria,
                        icon: _isBiometricLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(_iconoBiometrico, size: 24),
                        label: Text(
                          'ENTRAR CON $_labelBiometrico',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: Colors.green,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Conexión encriptada con BD Central',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CentroDeControlAdmin extends StatelessWidget {
  const CentroDeControlAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'SaaS POS',
            style: TextStyle(
              fontWeight: FontWeight.w300,
              fontSize: 24,
              letterSpacing: 2,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                // 🚨 Al cerrar sesión, limpiamos el token y las credenciales
                await prefs.remove('token_jwt');
                await prefs.remove('perfil_usuario');
                await prefs.remove('usuario_guardado');
                await prefs.remove('codigo_empresa');

                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.black,
            indicatorWeight: 3,
            labelStyle: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              fontSize: 12,
            ),
            tabs: [
              Tab(text: 'CENTRO DE CONTROL'),
              Tab(text: 'MOSTRADOR (CAJA)'),
            ],
          ),
        ),
        body: const TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [ModuloOficina(), ModuloPOS()],
        ),
      ),
    );
  }
}

class MostradorCajero extends StatelessWidget {
  const MostradorCajero({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PUNTO DE VENTA',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token_jwt');
              await prefs.remove('perfil_usuario');
              await prefs.remove('usuario_guardado');
              await prefs.remove('codigo_empresa');

              if (!context.mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: const ModuloPOS(),
    );
  }
}
