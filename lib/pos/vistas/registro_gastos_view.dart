import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// 🚨 VISTA 3: REGISTRO DE GASTOS (CÓDIGO LIMPIO SAAS)
// ============================================================================
class RegistroGastosView extends StatefulWidget {
  final Function(double) onGastoRegistrado;
  const RegistroGastosView({super.key, required this.onGastoRegistrado});

  @override
  State<RegistroGastosView> createState() => _RegistroGastosViewState();
}

class _RegistroGastosViewState extends State<RegistroGastosView> {
  final TextEditingController _conceptoController = TextEditingController();
  final TextEditingController _montoController = TextEditingController();
  final List<Map<String, dynamic>> _gastosDelDia = [];
  double _totalGastos = 0.0;

  @override
  void initState() {
    super.initState();
    _cargarGastosMemoria();
  }

  Future<void> _cargarGastosMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    final String? gastosStr = prefs.getString('caja_lista_gastos');

    if (gastosStr != null) {
      final List<dynamic> decoded = jsonDecode(gastosStr);
      double suma = 0;
      setState(() {
        _gastosDelDia.clear();
        for (var item in decoded) {
          var g = Map<String, dynamic>.from(item);
          _gastosDelDia.add(g);
          suma += g['monto'];
        }
        _totalGastos = suma;
      });
    }
  }

  Future<void> _guardarGastosMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('caja_lista_gastos', jsonEncode(_gastosDelDia));
  }

  void _registrarGasto() {
    final concepto = _conceptoController.text.trim();
    final monto = double.tryParse(_montoController.text) ?? 0.0;

    // 🚨 Corrección estricta de Dart (Llaves en el IF)
    if (concepto.isEmpty || monto <= 0) {
      return;
    }

    final now = DateTime.now();
    final horaStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _gastosDelDia.insert(0, {
        "concepto": concepto,
        "monto": monto,
        "hora": horaStr,
      });
      _totalGastos += monto;
      _conceptoController.clear();
      _montoController.clear();
      _guardarGastosMemoria();
    });

    widget.onGastoRegistrado(monto);
  }

  void _eliminarGasto(int index) {
    setState(() {
      _totalGastos -= _gastosDelDia[index]["monto"];
      widget.onGastoRegistrado(-_gastosDelDia[index]["monto"]);
      _gastosDelDia.removeAt(index);
      _guardarGastosMemoria();
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    Widget formNuevoGasto = Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NUEVO GASTO',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _conceptoController,
            decoration: const InputDecoration(
              labelText: 'Concepto (Ej. Papelería, Limpieza)',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Color(0xFFF9F9F9),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _montoController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Costo total (\$)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.attach_money),
              filled: true,
              fillColor: Color(0xFFF9F9F9),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 45,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text(
                'REGISTRAR SALIDA',
                style: TextStyle(letterSpacing: 1, fontWeight: FontWeight.bold),
              ),
              onPressed: _registrarGasto,
            ),
          ),
        ],
      ),
    );

    Widget listaSalidas = Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SALIDAS DE HOY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'TOTAL: -\$${_totalGastos.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            constraints: BoxConstraints(maxHeight: isMobile ? 250 : 400),
            child: _gastosDelDia.isEmpty
                ? const Center(
                    child: Text(
                      'Caja limpia. No hay gastos hoy.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _gastosDelDia.length,
                    separatorBuilder: (context, index) =>
                        const Divider(color: Colors.white24),
                    itemBuilder: (context, index) {
                      final gasto = _gastosDelDia[index];
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  gasto["concepto"],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  gasto["hora"],
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '-\$${gasto["monto"].toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                                onPressed: () => _eliminarGasto(index),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GASTOS OPERATIVOS',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Todo lo registrado aquí se restará del total de efectivo en caja.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 30),
              if (isMobile) ...[
                formNuevoGasto,
                const SizedBox(height: 20),
                listaSalidas,
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: formNuevoGasto),
                    const SizedBox(width: 32),
                    Expanded(flex: 3, child: listaSalidas),
                  ],
                ),
              ],
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
