import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class InteligenciaArtificialView extends StatefulWidget {
  const InteligenciaArtificialView({super.key});

  @override
  State<InteligenciaArtificialView> createState() =>
      _InteligenciaArtificialViewState();
}

class _InteligenciaArtificialViewState
    extends State<InteligenciaArtificialView> {
  final TextEditingController _mensajeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _estaCargando = false;

  final List<Map<String, dynamic>> _mensajes = [
    {
      "texto":
          "Hola. Soy tu IA Ejecutiva. He sido conectada a la base de datos de tu empresa con Visión Total.\n\nLeo en milisegundos tu inventario completo (SKUs, tallas, stock por sucursal), cortes de caja y cada venta que entra en el día en toda tu red de tiendas. Hazme preguntas precisas.",
      "esUsuario": false,
    },
  ];

  void _hacerScrollAlFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 🚨 EL CEREBRO ULTRA PRECISO (Adaptado al SaaS Multi-Sucursal)
  Future<String> _armarContextoProfundo() async {
    try {
      final resultados = await Future.wait([
        ApiService.obtenerInventario(),
        ApiService.obtenerVentasEnVivo(),
        ApiService.obtenerHistorialCortes(),
      ]);

      final List<dynamic> inventario = resultados[0];
      final List<dynamic> ventasHoy = resultados[1];
      final List<dynamic> cortes = resultados[2];

      StringBuffer ctx = StringBuffer();

      // INSTRUCCIONES ESTRICTAS PARA LA IA
      ctx.writeln(
        "INSTRUCCIÓN CRÍTICA DE SISTEMA: Eres una IA Ejecutiva de Análisis de Datos para esta empresa. A continuación se te proporciona un volcado de base de datos en tiempo real de TODAS LAS SUCURSALES. REGLAS: 1) Sé ultra preciso y matemático. 2) NUNCA inventes datos. Si algo no está en el contexto, di que no hay registro. 3) Usa las cantidades, sucursales y SKUs exactos provistos.\n",
      );

      // 1. INVENTARIO (Ahora incluye desglose de sucursales)
      ctx.writeln("--- INVENTARIO OMNICANAL ACTUALIZADO AL SEGUNDO ---");
      if (inventario.isEmpty) {
        ctx.writeln("INVENTARIO VACÍO: 0 productos.");
      } else {
        for (var p in inventario) {
          ctx.writeln(
            "[SKU: ${p['sku']}] Producto: '${p['nombre']}' | Stock Global: ${p['stock_bodega']} unidades | Desglose Sucursales/Tallas: ${p['tallas']} | Precio: \$${p['precio_venta']}",
          );
        }
      }

      // 2. VENTAS Y MOVIMIENTOS (Aislados por sucursal)
      ctx.writeln("\n--- MOVIMIENTOS DE HOY EN TODA LA RED ---");
      if (ventasHoy.isEmpty) {
        ctx.writeln("Sin movimientos registrados hoy.");
      } else {
        double totalHoy = 0.0;
        for (var v in ventasHoy) {
          ctx.writeln(
            "[SUCURSAL: ${v['sucursal_nombre'] ?? 'General'}] [HORA: ${v['hora_fmt']}] TIPO: ${v['tipo']} | MONTO: \$${v['monto']} | MÉTODO: ${v['metodo_pago'] ?? 'Efectivo'} | DESCRIPCIÓN: ${v['descripcion']}",
          );
          totalHoy += double.tryParse(v['monto'].toString()) ?? 0.0;
        }
        ctx.writeln(
          ">> FLUJO BRUTO DEL DÍA EN LA RED: \$${totalHoy.toStringAsFixed(2)}",
        );
      }

      // 3. CORTES HISTÓRICOS
      ctx.writeln("\n--- HISTÓRICO RECIENTE DE CAJA (CORTES POR SUCURSAL) ---");
      if (cortes.isEmpty) {
        ctx.writeln("Sin cortes en registro.");
      } else {
        int limite = cortes.length > 5 ? 5 : cortes.length;
        for (int i = 0; i < limite; i++) {
          var c = cortes[i];
          ctx.writeln(
            "[FECHA: ${c['fecha_formateada']}] [SUCURSAL: ${c['sucursal_nombre'] ?? 'General'}] Cajero: ${c['cajero']} | Ventas Totales: \$${c['ventas_totales']} (Ef: \$${c['ventas_efectivo']}, Tarj: \$${c['ventas_tarjeta']}) | Gastos: \$${c['gastos_totales']}",
          );
        }
      }

      ctx.writeln("\n=========================");
      ctx.writeln("CONSULTA EXACTA DEL DIRECTOR DE LA EMPRESA:");
      return ctx.toString();
    } catch (e) {
      return "Hubo un error de lectura. Responde en base a tu conocimiento previo. CONSULTA DEL USUARIO: ";
    }
  }

  Future<void> _enviarMensaje() async {
    final String preguntaVisual = _mensajeController.text.trim();
    if (preguntaVisual.isEmpty) {
      return;
    }

    setState(() {
      _mensajes.add({"texto": preguntaVisual, "esUsuario": true});
      _estaCargando = true;
    });
    _mensajeController.clear();
    _hacerScrollAlFondo();

    String contextoGigante = await _armarContextoProfundo();
    String preguntaConContexto = '$contextoGigante\n$preguntaVisual';

    final String respuesta = await ApiService.preguntarALaIA(
      preguntaConContexto,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _estaCargando = false;
      _mensajes.add({"texto": respuesta, "esUsuario": false});
    });
    _hacerScrollAlFondo();
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: Colors.deepPurpleAccent,
                  size: 30,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'CEREBRO IA',
                    style: TextStyle(
                      fontSize: isMobile ? 20 : 24,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Copiloto de Inteligencia de Negocios en Tiempo Real.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 30),

            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.deepPurple.shade100),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(24),
                        itemCount: _mensajes.length,
                        itemBuilder: (context, index) {
                          final msg = _mensajes[index];
                          return _burbujaChat(msg["texto"], msg["esUsuario"]);
                        },
                      ),
                    ),
                    if (_estaCargando)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.deepPurple,
                              ),
                            ),
                            SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                "Cruzando datos de la red de sucursales y analizando...",
                                style: TextStyle(
                                  color: Colors.deepPurple,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _mensajeController,
                              decoration: const InputDecoration(
                                hintText:
                                    'Ej. ¿Cuál fue la sucursal que más vendió hoy?',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Color(0xFFF9F9F9),
                              ),
                              onSubmitted: (_) => _enviarMensaje(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                                horizontal: 20,
                              ),
                            ),
                            onPressed: _estaCargando ? null : _enviarMensaje,
                            child: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _burbujaChat(String mensaje, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: isUser ? Colors.black : Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser
                ? const Radius.circular(0)
                : const Radius.circular(16),
            topLeft: !isUser
                ? const Radius.circular(0)
                : const Radius.circular(16),
          ),
          border: Border.all(
            color: isUser ? Colors.black : Colors.deepPurple.shade100,
          ),
        ),
        child: Text(
          mensaje,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
