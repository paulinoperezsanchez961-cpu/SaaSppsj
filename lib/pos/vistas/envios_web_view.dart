import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';

// ============================================================================
// 🚨 VISTA 6: ENVÍOS WEB (CONECTADO A BASE DE DATOS REAL SAAS)
// ============================================================================
class EnviosWebView extends StatefulWidget {
  const EnviosWebView({super.key});
  @override
  State<EnviosWebView> createState() => _EnviosWebViewState();
}

class _EnviosWebViewState extends State<EnviosWebView> {
  bool _isLoading = true;
  List<dynamic> _pedidosNuevos = [];

  // 🚨 OPTIMIZACIÓN DE MEMORIA: Se marcan como final porque solo se mutan internamente
  final List<dynamic> _pedidosEmpaque = [];
  final List<dynamic> _pedidosDespachados = [];

  final TextEditingController _guiaController = TextEditingController();
  final TextEditingController _paqueteriaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarPedidosWeb();
  }

  @override
  void dispose() {
    _guiaController.dispose();
    _paqueteriaController.dispose();
    super.dispose();
  }

  // 📡 DESCARGAR PEDIDOS PAGADOS Y SEGUROS DESDE EL SERVIDOR
  Future<void> _cargarPedidosWeb() async {
    setState(() => _isLoading = true);
    try {
      // 🚨 SAAS FIX: Headers de Autenticación Inyectados
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/bodega/pedidos-pendientes'),
        headers: await ApiService.getAuthHeaders(),
      );

      if (!mounted) {
        return;
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['exito'] == true) {
          setState(() {
            _pedidosNuevos = data['pedidos'] ?? [];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al conectar con el servidor.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _comenzarEmpaque(int index) {
    setState(() {
      _pedidosEmpaque.insert(0, _pedidosNuevos.removeAt(index));
    });
  }

  // 📡 ACTUALIZAR LA GUÍA Y PAQUETERÍA EN EL SERVIDOR
  Future<void> _ejecutarDespachoServidor(int index) async {
    final paqueteria = _paqueteriaController.text.trim();
    final guia = _guiaController.text.trim();

    if (paqueteria.isEmpty || guia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Debes ingresar paquetería y número de guía.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final pedido = _pedidosEmpaque[index];
    final String idPedido = pedido['id'].toString();

    Navigator.pop(context); // Cierra el modal de diálogo

    // Muestra un loader en la pantalla
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.black)),
    );

    try {
      // 🚨 SAAS FIX: Headers de Autenticación Inyectados
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/bodega/despachar/$idPedido'),
        headers: await ApiService.getAuthHeaders(),
        body: jsonEncode({'paqueteria': paqueteria, 'guia_rastreo': guia}),
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context); // Cierra el loader

      final data = jsonDecode(res.body);

      if (data['exito'] == true) {
        setState(() {
          final p = _pedidosEmpaque.removeAt(index);
          p['paqueteria'] = paqueteria;
          p['guia_rastreo'] = guia;
          _pedidosDespachados.insert(0, p);
          _guiaController.clear();
          _paqueteriaController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Pedido #$idPedido despachado correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error en BD al guardar la guía.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      Navigator.pop(context); // Cierra el loader
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error de conexión al despachar.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _despacharPedido(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Despachar Pedido #${_pedidosEmpaque[index]['id']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _paqueteriaController,
              decoration: const InputDecoration(
                labelText: 'Paquetería (ej. FedEx, Estafeta)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _guiaController,
              decoration: const InputDecoration(
                labelText: 'Número de Guía de Rastreo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _guiaController.clear();
              _paqueteriaController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => _ejecutarDespachoServidor(index),
            child: const Text(
              'Confirmar Envío',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: DefaultTabController(
        length: 3,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ENVÍOS WEB',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 3,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _cargarPedidosWeb,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('ACTUALIZAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const TabBar(
                labelColor: Colors.black,
                indicatorColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'NUEVOS PEDIDOS'),
                  Tab(text: 'EN EMPAQUE'),
                  Tab(text: 'DESPACHADOS (HOY)'),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildLista(_pedidosNuevos, 0),
                    _buildLista(_pedidosEmpaque, 1),
                    _buildLista(_pedidosDespachados, 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLista(List<dynamic> lista, int tab) {
    if (_isLoading && tab == 0) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }

    if (lista.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 60, color: Colors.black12),
            SizedBox(height: 10),
            Text(
              'Bandeja limpia. No hay pedidos aquí.',
              style: TextStyle(color: Colors.grey, letterSpacing: 1),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: lista.length,
      itemBuilder: (c, i) {
        final p = lista[i];

        // Formateo del string de info_envio para que se vea como una tarjeta limpia
        final String infoBruta = p['info_envio'] ?? '';
        final List<String> detallesEnvio = infoBruta
            .split('|')
            .map((e) => e.trim())
            .toList();

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PEDIDO #${p['id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Colors.blueAccent,
                      ),
                    ),
                    Text(
                      '\$${p['total']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                Text(
                  '👤 ${p['cliente']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),

                // Imprimimos la información de envío desglosada
                ...detallesEnvio.map(
                  (linea) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      '📍 $linea',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
                Text(
                  '💳 Pago: ${p['metodo_pago'] ?? 'Confirmado Seguro'}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 20),

                if (tab == 0)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.inventory_2),
                      label: const Text(
                        'COMENZAR A EMPAQUETAR',
                        style: TextStyle(
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () => _comenzarEmpaque(i),
                    ),
                  ),

                if (tab == 1)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.local_shipping),
                      label: const Text(
                        'DESPACHAR A PAQUETERÍA',
                        style: TextStyle(
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _despacharPedido(i),
                    ),
                  ),

                if (tab == 2)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'ENVIADO Y REGISTRADO',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Paquetería: ${p['paqueteria']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Guía: ${p['guia_rastreo']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
