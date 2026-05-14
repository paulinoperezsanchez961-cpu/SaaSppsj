import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/api_service.dart';

class VentasEnVivoView extends StatefulWidget {
  const VentasEnVivoView({super.key});

  @override
  State<VentasEnVivoView> createState() => _VentasEnVivoViewState();
}

class _VentasEnVivoViewState extends State<VentasEnVivoView> {
  List<dynamic> _ventasVisibles = [];
  bool _cargando = true;
  Timer? _timer;

  String _filtroActivo = 'Hoy';

  // 🚨 SISTEMA MULTI-SUCURSAL
  List<String> _sucursalesDisponibles = ['Todas'];
  String _sucursalSeleccionada = 'Todas';

  @override
  void initState() {
    super.initState();
    _cargarVentasReales();
    // 🚨 AUTO-REFRESH: Se actualiza solo cada 30 segundos
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _cargarVentasReales(silencioso: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatearFechaBD(DateTime fecha) {
    return '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
  }

  Future<void> _cargarVentasReales({bool silencioso = false}) async {
    if (!silencioso && mounted) {
      setState(() => _cargando = true);
    }

    DateTime hoy = DateTime.now();
    String? fechaInicio;
    String? fechaFin;

    if (_filtroActivo == 'Esta Semana') {
      int diasRestar = hoy.weekday == 7 ? 0 : hoy.weekday;
      DateTime ultimoDomingo = hoy.subtract(Duration(days: diasRestar));

      fechaInicio = _formatearFechaBD(ultimoDomingo);
      fechaFin = _formatearFechaBD(hoy);
    } else {
      fechaInicio = _formatearFechaBD(hoy);
      fechaFin = _formatearFechaBD(hoy);
    }

    final datos = await ApiService.obtenerVentasEnVivo(
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
    );

    if (mounted) {
      // 🚨 EXTRAER SUCURSALES ÚNICAS
      Set<String> sucursalesSet = {'Todas'};
      for (var v in datos) {
        String nombreSucursal = v['sucursal_nombre'] ?? 'Web/General';
        sucursalesSet.add(nombreSucursal);
      }

      setState(() {
        _ventasVisibles = datos;
        _sucursalesDisponibles = sucursalesSet.toList();

        // Si la sucursal seleccionada ya no tiene ventas hoy, volver a "Todas"
        if (!_sucursalesDisponibles.contains(_sucursalSeleccionada)) {
          _sucursalSeleccionada = 'Todas';
        }

        _cargando = false;
      });
    }
  }

  // 🚨 FILTRO INTELIGENTE POR SUCURSAL
  List<dynamic> get _ventasFiltradas {
    if (_sucursalSeleccionada == 'Todas') {
      return _ventasVisibles;
    }
    return _ventasVisibles.where((v) {
      String nombre = v['sucursal_nombre'] ?? 'Web/General';
      return nombre == _sucursalSeleccionada;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    // 🚨 CÁLCULO FINANCIERO RIGUROSO EN VIVO (Basado solo en las ventas filtradas)
    double totalPeriodo = 0;
    double totalEfectivo = 0;
    double totalTarjeta = 0;
    double totalTransferencia = 0;

    final ventasAProcesar = _ventasFiltradas;

    for (var v in ventasAProcesar) {
      double monto = double.tryParse(v['monto'].toString()) ?? 0;
      String metodo = v['metodo_pago'] ?? 'Efectivo';

      // 🚨 PARCHE FINANCIERO: El "Total Bruto" solo debe sumar lo que entra, nunca restar gastos.
      if (monto > 0) {
        totalPeriodo += monto;
      }

      // Los totales por método de pago SÍ deben sumar/restar para decirnos cuánto hay físicamente
      if (metodo.contains('Tarjeta') || metodo.contains('Stripe')) {
        totalTarjeta += monto;
      } else if (metodo.contains('Transferencia')) {
        totalTransferencia += monto;
      } else {
        // Todo lo demás (Efectivo local, OXXO Efectivo, PayPal) cae en la sumatoria general de líquido
        totalEfectivo += monto;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🎨 HEADER MÁS LIMPIO Y RESPONSIVO
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MONITOR EN VIVO',
                          style: TextStyle(
                            fontSize: isMobile ? 22 : 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Sincronización automática de sucursales cada 30s',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile) _buildFiltrosYRefresh(),
                ],
              ),
              if (isMobile) ...[
                const SizedBox(height: 16),
                _buildFiltrosYRefresh(),
              ],
              const SizedBox(height: 24),

              // 🎨 DASHBOARD MODERNO
              Text(
                _filtroActivo == 'Hoy'
                    ? 'CAJA ACTUAL (HOY)'
                    : 'CAJA ACUMULADA (SEMANA)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.black54,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 12),

              GridView.count(
                crossAxisCount: isMobile ? 2 : 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isMobile ? 1.8 : 2.2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildKpiCard(
                    'TOTAL BRUTO',
                    totalPeriodo,
                    Colors.black87,
                    Colors.white,
                    Icons.account_balance_wallet,
                  ),
                  _buildKpiCard(
                    'EFECTIVO / OTROS',
                    totalEfectivo,
                    Colors.green.shade700,
                    Colors.green.shade50,
                    Icons.payments,
                  ),
                  _buildKpiCard(
                    'TARJETAS / WEB',
                    totalTarjeta,
                    Colors.blue.shade700,
                    Colors.blue.shade50,
                    Icons.credit_card,
                  ),
                  _buildKpiCard(
                    'TRANSFERENCIA',
                    totalTransferencia,
                    Colors.purple.shade700,
                    Colors.purple.shade50,
                    Icons.compare_arrows,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 🎨 LISTA DE VENTAS TIPO "TIMELINE"
              const Text(
                'ÚLTIMOS MOVIMIENTOS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.black54,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _cargando && ventasAProcesar.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.black),
                      )
                    : ventasAProcesar.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Sin movimientos en este periodo o sucursal.",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: ventasAProcesar.length,
                        itemBuilder: (context, index) {
                          final v = ventasAProcesar[index];
                          final String tipo = v['tipo'] ?? '';
                          final String desc =
                              v['descripcion'] ?? 'Sin detalles';
                          final double monto =
                              double.tryParse(v['monto'].toString()) ?? 0;
                          final String hora = v['hora_fmt'] ?? '';
                          final String fecha = v['fecha_fmt'] ?? '';
                          final String metodoPago =
                              v['metodo_pago'] ?? 'Efectivo';
                          final String sucursalNombre =
                              v['sucursal_nombre'] ?? 'Web/General';

                          bool mostrarFecha = false;
                          if (index == 0) {
                            mostrarFecha = true;
                          } else {
                            final String fechaAnterior =
                                ventasAProcesar[index - 1]['fecha_fmt'] ?? '';
                            if (fecha != fechaAnterior) {
                              mostrarFecha = true;
                            }
                          }

                          // 🚨 AQUÍ EL RADAR DETECTA EL TIPO Y LE DA COLOR
                          Color colorIcono = Colors.grey;
                          IconData icono = Icons.info;
                          Color bgIcono = Colors.grey.shade100;

                          if (tipo == 'VENTA_POS') {
                            colorIcono = Colors.green.shade600;
                            bgIcono = Colors.green.shade50;
                            icono = Icons.point_of_sale;
                          } else if (tipo == 'VENTA_WEB') {
                            colorIcono = Colors.blue.shade600;
                            bgIcono = Colors.blue.shade50;
                            icono = Icons.shopping_cart;
                          } else if (tipo == 'LIQUIDACION_APARTADO') {
                            colorIcono = Colors.red.shade600;
                            bgIcono = Colors.red.shade50;
                            icono = Icons.task_alt;
                          } else if (tipo == 'ABONO_APARTADO') {
                            colorIcono = Colors.teal.shade600;
                            bgIcono = Colors.teal.shade50;
                            icono = Icons.payments_outlined;
                          } else if (tipo == 'ENGANCHE_APARTADO') {
                            colorIcono = Colors.amber.shade700;
                            bgIcono = Colors.amber.shade50;
                            icono = Icons.bookmark_added;
                          } else if (tipo == 'CAMBIO_FISICO') {
                            colorIcono = Colors.deepPurple.shade500;
                            bgIcono = Colors.deepPurple.shade50;
                            icono = Icons.swap_horiz;
                          } else if (tipo == 'PAGO_COMISIONES') {
                            colorIcono = Colors.redAccent;
                            bgIcono = Colors.red.shade50;
                            icono = Icons.money_off;
                          }

                          // 🚨 BADGES INTELIGENTES PARA MÉTODOS DE PAGO WEB Y FÍSICOS
                          bool esTarjeta =
                              metodoPago.contains('Tarjeta') ||
                              metodoPago.contains('Stripe');
                          bool esTransf = metodoPago.contains('Transferencia');
                          bool esPaypal = metodoPago.toLowerCase().contains(
                            'paypal',
                          );
                          bool esOxxo = metodoPago.toUpperCase().contains(
                            'OXXO',
                          );

                          Color colorMetodo = Colors.green.shade700;
                          IconData iconMetodo = Icons.money;

                          if (esTarjeta) {
                            colorMetodo = Colors.blue.shade700;
                            iconMetodo = Icons.credit_card;
                          } else if (esTransf) {
                            colorMetodo = Colors.purple.shade700;
                            iconMetodo = Icons.compare_arrows;
                          } else if (esPaypal) {
                            colorMetodo = Colors.indigo.shade600;
                            iconMetodo = Icons.language;
                          } else if (esOxxo) {
                            colorMetodo = Colors.orange.shade700;
                            iconMetodo = Icons.storefront;
                          }

                          // 🎨 TARJETA DE MOVIMIENTO
                          Widget tarjetaVenta = Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: bgIcono,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    icono,
                                    color: colorIcono,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              tipo.replaceAll('_', ' '),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: colorIcono,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            hora,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        desc,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.4,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Icon(
                                            iconMetodo,
                                            size: 12,
                                            color: colorMetodo,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              metodoPago,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: colorMetodo,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          // 🚨 MOSTRAR SUCURSAL SI SE ESTÁN VIENDO TODAS
                                          if (_sucursalSeleccionada == 'Todas')
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                sucursalNombre,
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '\$${monto.abs().toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: monto < 0
                                            ? Colors.redAccent
                                            : Colors.black87,
                                      ),
                                    ),
                                    if (monto < 0) ...[
                                      const SizedBox(height: 4),
                                      const Text(
                                        'SALIDA',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );

                          if (mostrarFecha) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 12,
                                    left: 4,
                                  ),
                                  child: Text(
                                    '🗓️ $fecha',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      color: Colors.black54,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                tarjetaVenta,
                              ],
                            );
                          }

                          return tarjetaVenta;
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🎨 BOTONES DE HEADER CON SELECTOR DE SUCURSALES
  Widget _buildFiltrosYRefresh() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Dropdown de Sucursal
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sucursalSeleccionada,
              icon: const Icon(Icons.storefront, size: 16, color: Colors.blue),
              items: _sucursalesDisponibles.map((String sucursal) {
                return DropdownMenuItem<String>(
                  value: sucursal,
                  child: Text(
                    sucursal,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _sucursalSeleccionada = val;
                  });
                }
              },
            ),
          ),
        ),

        // Dropdown de Fechas
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filtroActivo,
              icon: const Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: Colors.black54,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Hoy',
                  child: Text(
                    'Solo Hoy',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                DropdownMenuItem(
                  value: 'Esta Semana',
                  child: Text(
                    'Esta Semana',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filtroActivo = val;
                  });
                  _cargarVentasReales();
                }
              },
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => _cargarVentasReales(),
            child: const Icon(Icons.refresh, size: 18),
          ),
        ),
      ],
    );
  }

  // 🎨 TARJETAS DE DASHBOARD INDIVIDUALES
  Widget _buildKpiCard(
    String title,
    double amount,
    Color color,
    Color bg,
    IconData icon, {
    bool isHero = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHero ? color : color.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    color: isHero ? color : Colors.grey,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '\$${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: isHero ? 26 : 22,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
