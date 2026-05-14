import 'package:flutter/material.dart';
import '../../services/api_service.dart';

// 🚨 Enum para controlar la inteligencia de la pantalla
enum ModoVista { escanear, registrar, info, traspaso }

class RegistroVipView extends StatefulWidget {
  // 🚨 Variables opcionales: Si la terminal de cobro manda al cajero aquí,
  // la pantalla se pondrá automáticamente en "Modo Traspaso".
  final String? qrViejoTraspaso;
  final String? nivelTraspaso;

  const RegistroVipView({super.key, this.qrViejoTraspaso, this.nivelTraspaso});

  @override
  State<RegistroVipView> createState() => _RegistroVipViewState();
}

class _RegistroVipViewState extends State<RegistroVipView> {
  final TextEditingController _qrController = TextEditingController();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _qrFocusNode = FocusNode();

  bool _isLoading = false;
  ModoVista _modo = ModoVista.escanear;
  String _qrActual = '';
  Map<String, dynamic>? _infoCliente;

  @override
  void initState() {
    super.initState();
    // Si viene rebotado de la caja por una alerta de 10 compras...
    if (widget.qrViejoTraspaso != null && widget.nivelTraspaso != null) {
      _modo = ModoVista.traspaso;
    }
    // Forzamos el foco en el campo oculto para que la pistola láser funcione directo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _qrFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _qrController.dispose();
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _qrFocusNode.dispose();
    super.dispose();
  }

  // =========================================================================
  // 🧠 CEREBRO DEL ESCÁNER (Determina qué hacer con el QR)
  // =========================================================================
  Future<void> _procesarQR(String qrEscaneado) async {
    final qr = qrEscaneado.trim();
    if (qr.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_modo == ModoVista.traspaso) {
        // 🚨 REGLA DE SEGURIDAD FÍSICA: Oro=2, Titanio=3
        String prefijoEsperado = widget.nivelTraspaso == 'oro' ? '2' : '3';

        if (!qr.startsWith('$prefijoEsperado-')) {
          throw Exception(
            'La tarjeta física es incorrecta. Saca una virgen de nivel ${widget.nivelTraspaso?.toUpperCase()} (Debe iniciar con $prefijoEsperado-).',
          );
        }

        var res = await ApiService.traspasarVIP(
          widget.qrViejoTraspaso!,
          qr,
          widget.nivelTraspaso!,
        );

        if (!mounted) {
          return;
        }

        if (res['exito'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Traspaso exitoso a Nivel ${widget.nivelTraspaso?.toUpperCase()}',
              ),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _modo = ModoVista.escanear; // Regresa a la normalidad
            _qrController.clear();
          });
        } else {
          throw Exception(res['error'] ?? 'Error desconocido');
        }
      } else {
        // MODO NORMAL: Averiguar si la tarjeta es virgen o ya tiene dueño
        var res = await ApiService.consultarQRVIP(qr);

        if (!mounted) {
          return;
        }

        if (res['registrado'] == true) {
          setState(() {
            _infoCliente = res['cliente'];
            _modo = ModoVista.info; // Ya tiene dueño
          });
        } else {
          setState(() {
            _qrActual = qr;
            _modo = ModoVista.registrar; // Está virgen, pide datos
          });
        }
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _qrController.clear();
        _qrFocusNode.requestFocus();
      }
    }
  }

  Future<void> _registrarCliente() async {
    final nombre = _nombreController.text.trim();
    final telefono = _telefonoController.text.trim();
    final email = _emailController.text.trim();

    if (nombre.isEmpty || telefono.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, llena todos los campos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 🚨 Ahora mandamos el QR FÍSICO en lugar de inventar uno
      var res = await ApiService.registrarVIP(
        nombre,
        email,
        telefono,
        _qrActual,
      );

      if (!mounted) {
        return;
      }

      if (res['exito'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Tarjeta vinculada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _modo = ModoVista.escanear;
          _nombreController.clear();
          _telefonoController.clear();
          _emailController.clear();
          _qrActual = '';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${res['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      debugPrint('Aviso registro VIP: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error de conexión'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // =========================================================================
  // 🎨 BLOQUES DE INTERFAZ INTELIGENTE
  // =========================================================================

  Widget _buildEscanear() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.qr_code_scanner, size: 80, color: Colors.black87),
        const SizedBox(height: 24),
        const Text(
          'ESCANEA UNA TARJETA VIP',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'El sistema detectará si la tarjeta es nueva (virgen) o si ya pertenece a un cliente activo.',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: 350,
          child: TextField(
            controller: _qrController,
            focusNode: _qrFocusNode,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Pistola Láser / Código QR',
              prefixIcon: Icon(Icons.camera_alt),
              border: OutlineInputBorder(),
            ),
            onSubmitted: _procesarQR,
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: Colors.black),
          ),
      ],
    );
  }

  Widget _buildRegistrar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NUEVO SOCIO VIP',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.credit_card, color: Colors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Vinculando a tarjeta virgen:\n$_qrActual',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nombreController,
          decoration: const InputDecoration(
            labelText: 'Nombre Completo',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _telefonoController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo Electrónico',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _modo = ModoVista.escanear;
                  _qrActual = '';
                }),
                child: const Text(
                  'CANCELAR',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isLoading ? null : _registrarCliente,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text('GUARDAR'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTraspaso() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.upgrade, size: 80, color: Colors.amber.shade600),
        const SizedBox(height: 24),
        Text(
          'ASCENSO A NIVEL ${widget.nivelTraspaso?.toUpperCase()}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Transfiriendo datos de la tarjeta vieja:\n${widget.qrViejoTraspaso}',
          style: const TextStyle(
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        const Text(
          'Toma una tarjeta VIRGEN del nuevo nivel del cajón y escanéala aquí.',
          style: TextStyle(color: Colors.black87, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: 350,
          child: TextField(
            controller: _qrController,
            focusNode: _qrFocusNode,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Escanear NUEVA Tarjeta',
              prefixIcon: Icon(Icons.camera_alt),
              border: OutlineInputBorder(),
            ),
            onSubmitted: _procesarQR,
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: Colors.black),
          ),
      ],
    );
  }

  Widget _buildInfo() {
    if (_infoCliente == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_user, size: 80, color: Colors.green),
        const SizedBox(height: 24),
        const Text(
          'TARJETA ACTIVA',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text('Nombre'),
          subtitle: Text(
            _infoCliente!['nombre'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.star),
          title: const Text('Nivel'),
          subtitle: Text(
            _infoCliente!['nivel_vip'].toString().toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet),
          title: const Text('Cashback Disponible'),
          subtitle: Text(
            '\$${_infoCliente!['saldo_cashback']}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
          ),
          onPressed: () {
            setState(() => _modo = ModoVista.escanear);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _qrFocusNode.requestFocus(),
            );
          },
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('ESCANEAR OTRA TARJETA'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget contenido;
    switch (_modo) {
      case ModoVista.escanear:
        contenido = _buildEscanear();
        break;
      case ModoVista.registrar:
        contenido = _buildRegistrar();
        break;
      case ModoVista.info:
        contenido = _buildInfo();
        break;
      case ModoVista.traspaso:
        contenido = _buildTraspaso();
        break;
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: SizedBox(
                width: 500, // Una tarjeta blanca limpia en el centro
                child: contenido,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
