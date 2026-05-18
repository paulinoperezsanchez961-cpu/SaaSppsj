import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class ConfiguracionOficinaView extends StatefulWidget {
  const ConfiguracionOficinaView({super.key});

  @override
  State<ConfiguracionOficinaView> createState() =>
      _ConfiguracionOficinaViewState();
}

class _ConfiguracionOficinaViewState extends State<ConfiguracionOficinaView> {
  // Controles de Seguridad
  final TextEditingController _clavePosCtrl = TextEditingController();
  final TextEditingController _claveOficinaCtrl = TextEditingController();

  // 🚨 NUEVOS CONTROLES: Identidad y Hardware de Impresión
  final TextEditingController _nombreEmpresaCtrl = TextEditingController();
  final TextEditingController _direccionEmpresaCtrl = TextEditingController();
  double _anchoImpresora = 80.0; // Por defecto 80mm

  // Controles de APIs y Personalización
  final TextEditingController _mensajeTicketCtrl = TextEditingController();
  final TextEditingController _mpTokenCtrl = TextEditingController();
  final TextEditingController _mpDeviceCtrl = TextEditingController();
  final TextEditingController _clipKeyCtrl = TextEditingController();
  final TextEditingController _geminiKeyCtrl = TextEditingController();
  final TextEditingController _correoResendCtrl = TextEditingController();

  String _logoUrl = "";
  bool _cargando = true;
  bool _guardando = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cargarConfiguracionActual();
  }

  Future<void> _cargarConfiguracionActual() async {
    final llaves = await ApiService.obtenerLlavesAPI();

    if (mounted) {
      setState(() {
        _logoUrl = llaves['logo_empresa'] ?? "";
        _nombreEmpresaCtrl.text = llaves['nombre_empresa'] ?? "";
        _direccionEmpresaCtrl.text = llaves['direccion_empresa'] ?? "";
        _anchoImpresora =
            double.tryParse(llaves['ancho_impresora']?.toString() ?? '80') ??
            80.0;

        _mensajeTicketCtrl.text = llaves['mensaje_ticket'] ?? "";
        _mpTokenCtrl.text = llaves['mp_access_token'] ?? "";
        _mpDeviceCtrl.text = llaves['mp_device_id'] ?? "";
        _clipKeyCtrl.text = llaves['clip_api_key'] ?? "";
        _geminiKeyCtrl.text = llaves['gemini_api_key'] ?? "";
        _correoResendCtrl.text = llaves['correo_remitente'] ?? "";
        _cargando = false;
      });
    }
  }

  Future<void> _subirNuevoLogo() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _guardando = true);

    try {
      final bytes = await image.readAsBytes();
      String? urlSubida = await ApiService.subirLogoEmpresa(bytes, image.name);

      if (!mounted) return;

      if (urlSubida != null) {
        setState(() {
          _logoUrl = urlSubida;
        });

        // Auto-guardamos la config para que el logo se fije de inmediato
        await _guardarAjustesSaaS();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo actualizado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al subir la imagen'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fallo en la subida del archivo'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _actualizarClaves() async {
    final clavePos = _clavePosCtrl.text.trim();
    final claveOficina = _claveOficinaCtrl.text.trim();

    if (clavePos.isEmpty && claveOficina.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe al menos una contraseña para actualizar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    bool exito = await ApiService.cambiarClaves(clavePos, claveOficina);

    if (!mounted) return;

    if (exito) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contraseñas actualizadas con éxito'),
          backgroundColor: Colors.green,
        ),
      );
      _clavePosCtrl.clear();
      _claveOficinaCtrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al actualizar las contraseñas'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _guardando = false);
  }

  Future<void> _guardarAjustesSaaS() async {
    setState(() => _guardando = true);

    Map<String, dynamic> llavesAActualizar = {
      "logo_empresa": _logoUrl,
      "nombre_empresa": _nombreEmpresaCtrl.text.trim(),
      "direccion_empresa": _direccionEmpresaCtrl.text.trim(),
      "ancho_impresora": _anchoImpresora,
      "mensaje_ticket": _mensajeTicketCtrl.text.trim(),
      "mp_access_token": _mpTokenCtrl.text.trim(),
      "mp_device_id": _mpDeviceCtrl.text.trim(),
      "clip_api_key": _clipKeyCtrl.text.trim(),
      "gemini_api_key": _geminiKeyCtrl.text.trim(),
      "correo_remitente": _correoResendCtrl.text.trim(),
    };

    bool exito = await ApiService.guardarLlavesAPI(llavesAActualizar);

    if (!mounted) return;

    if (exito) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('caja_logo_empresa', _logoUrl);
      await prefs.setString(
        'caja_nombre_empresa',
        _nombreEmpresaCtrl.text.trim(),
      );
      await prefs.setString(
        'caja_direccion_empresa',
        _direccionEmpresaCtrl.text.trim(),
      );
      await prefs.setDouble('caja_ancho_impresora', _anchoImpresora);
      await prefs.setString(
        'caja_mensaje_ticket',
        _mensajeTicketCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Configuración del negocio guardada'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error al guardar configuración'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    if (_cargando) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AJUSTES DE EMPRESA Y SISTEMA',
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 3,
                          ),
                        ),
                        const Text(
                          'Personaliza tu imagen, seguridad y métodos de cobro.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                      ),
                      icon: _guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text(
                        'GUARDAR AJUSTES',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      onPressed: _guardando ? null : _guardarAjustesSaaS,
                    ),
                ],
              ),
              const SizedBox(height: 30),

              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  // 1. IDENTIDAD DE LA EMPRESA (TICKETS Y MARCA)
                  SizedBox(
                    width: isMobile ? double.infinity : 400,
                    child: _panelAjustes(
                      'IDENTIDAD CORPORATIVA',
                      'Este logo y mensaje aparecerá en los tickets de tus clientes y en tu tienda en línea.',
                      Colors.blue.shade700,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: InkWell(
                              onTap: _subirNuevoLogo,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _logoUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          _logoUrl,
                                          fit: BoxFit.contain,
                                          errorBuilder: (c, e, s) => const Icon(
                                            Icons.image_not_supported,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      )
                                    : const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_a_photo,
                                            color: Colors.blue,
                                            size: 30,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Subir Logo',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _nombreEmpresaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nombre de la Empresa (Para tickets)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.storefront, size: 16),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _direccionEmpresaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Dirección o Sucursal Principal',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.location_on, size: 16),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Ancho de tu Impresora de Tickets:',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<double>(
                            initialValue:
                                _anchoImpresora, // 🚨 CORRECCIÓN DEL LINTER
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.print, size: 16),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 80.0,
                                child: Text(
                                  '80mm (Impresora de Escritorio)',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 58.0,
                                child: Text(
                                  '58mm (Mini Impresora Portátil)',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _anchoImpresora = val);
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _mensajeTicketCtrl,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Mensaje al final del Ticket',
                              hintText:
                                  'Ej. Gracias por su compra, vuelva pronto.',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. TERMINALES DE COBRO (MERCADO PAGO Y CLIP)
                  SizedBox(
                    width: isMobile ? double.infinity : 400,
                    child: _panelAjustes(
                      'TERMINALES INTELIGENTES',
                      'Conecta tus terminales para que el sistema cobre de forma automática.',
                      Colors.cyan.shade700,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MERCADO PAGO POINT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.cyan,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _mpTokenCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Access Token de Producción',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.key, size: 16),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _mpDeviceCtrl,
                            decoration: const InputDecoration(
                              labelText: 'ID de Terminal (Device ID)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.point_of_sale, size: 16),
                            ),
                          ),
                          const Divider(height: 30),
                          const Text(
                            'TERMINALES CLIP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _clipKeyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Clip API Key',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.key, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3. INTEGRACIONES IA Y CORREOS
                  SizedBox(
                    width: isMobile ? double.infinity : 400,
                    child: _panelAjustes(
                      'CEREBRO E INTEGRACIONES',
                      'Conecta el motor de IA y el enviador de correos VIP.',
                      Colors.deepPurple,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _geminiKeyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Google Gemini API Key (IA)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.auto_awesome, size: 16),
                            ),
                          ),
                          const SizedBox(height: 15),
                          TextField(
                            controller: _correoResendCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'Remitente VIP (Ej: contacto@miempresa.com)',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.mail, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 4. SEGURIDAD DE ACCESO
                  SizedBox(
                    width: isMobile ? double.infinity : 400,
                    child: _panelAjustes(
                      'SEGURIDAD Y CONTRASEÑAS',
                      'Modifica las claves maestras. Deja en blanco las que no quieras cambiar.',
                      Colors.red,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _clavePosCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Nueva Contraseña de CAJA',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.lock_outline, size: 16),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _claveOficinaCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Nueva Contraseña de OFICINA',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.security, size: 16),
                            ),
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              onPressed: _guardando ? null : _actualizarClaves,
                              child: const Text(
                                'CAMBIAR CONTRASEÑAS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              if (isMobile) ...[
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    icon: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: const Text(
                      'GUARDAR AJUSTES',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    onPressed: _guardando ? null : _guardarAjustesSaaS,
                  ),
                ),
              ],

              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelAjustes(
    String titulo,
    String subtitulo,
    Color colorLinea,
    Widget contenido,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 6,
            decoration: BoxDecoration(
              color: colorLinea,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: colorLinea,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitulo,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  contenido,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
