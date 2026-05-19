import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../main.dart';

class SuperAdminView extends StatefulWidget {
  const SuperAdminView({super.key});

  @override
  State<SuperAdminView> createState() => _SuperAdminViewState();
}

class _SuperAdminViewState extends State<SuperAdminView> {
  List<dynamic> _empresas = [];
  bool _cargando = true;
  String _busqueda = "";

  @override
  void initState() {
    super.initState();
    _cargarEmpresas();
  }

  Future<void> _cargarEmpresas() async {
    setState(() => _cargando = true);
    final empresas = await ApiService.obtenerTodasLasEmpresas();
    if (mounted) {
      setState(() {
        _empresas = empresas;
        _cargando = false;
      });
    }
  }

  Future<void> _cambiarEstado(String codigo, bool suspendidaActual) async {
    final sm = ScaffoldMessenger.of(context);

    bool confirmacion =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              suspendidaActual ? '¿Reactivar Licencia?' : '¿Suspender Empresa?',
            ),
            content: Text(
              suspendidaActual
                  ? 'La empresa $codigo volverá a tener acceso al sistema SaaS inmediatamente.'
                  : 'Se le cortará el acceso a la oficina y cajas a la empresa $codigo por falta de pago. Sus datos se mantendrán en el servidor.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: suspendidaActual ? Colors.green : Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(suspendidaActual ? 'REACTIVAR' : 'SUSPENDER'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) {
      return;
    }

    if (confirmacion) {
      setState(() => _cargando = true);
      bool exito = await ApiService.cambiarEstadoEmpresa(
        codigo,
        !suspendidaActual,
      );

      if (!mounted) {
        return;
      }

      if (exito) {
        _cargarEmpresas();
      } else {
        setState(() => _cargando = false);
        sm.showSnackBar(
          const SnackBar(
            content: Text('Error al contactar con el servidor.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==========================================================
  // 🚀 NUEVA FUNCIÓN: MEJORAR PLAN (UPGRADE)
  // ==========================================================
  void _mostrarDialogoMejorarPlan(String codigoEmpresa, String planActual) {
    String nivelPlan = 'Completa';
    String duracionPlan = 'Mensual';
    int limiteSucursales = 999;
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctxDialog) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.rocket_launch, color: Colors.blueAccent),
              SizedBox(width: 10),
              Text('Hacer Upgrade (Mejorar Plan)'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modificando los límites operativos para la empresa:\n$codigoEmpresa',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Modalidad de Pago:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: duracionPlan,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Permanente',
                      child: Text('Pago Único (Permanente)'),
                    ),
                    DropdownMenuItem(
                      value: 'Mensual',
                      child: Text('Suscripción Mensual'),
                    ),
                    DropdownMenuItem(
                      value: 'Anual',
                      child: Text('Suscripción Anual'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setStateDialog(() => duracionPlan = val);
                    }
                  },
                ),
                const SizedBox(height: 15),
                const Text(
                  'Nuevo Nivel de Plan:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: nivelPlan,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Básica',
                      child: Text(
                        'Básica (1 Sucursal)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Media',
                      child: Text(
                        'Media (Hasta 3 Sucursales)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Completa',
                      child: Text(
                        'Completa (Ilimitado)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setStateDialog(() {
                        nivelPlan = val;
                        if (val == 'Básica') {
                          limiteSucursales = 1;
                        }
                        if (val == 'Media') {
                          limiteSucursales = 3;
                        }
                        if (val == 'Completa') {
                          limiteSucursales = 999;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'Límite asignado: $limiteSucursales sucursal(es).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctxDialog),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: guardando
                  ? null
                  : () async {
                      setStateDialog(() => guardando = true);

                      final nav = Navigator.of(ctxDialog);
                      final sm = ScaffoldMessenger.of(context);
                      final planFinalBD = '$duracionPlan - $nivelPlan';

                      final exito = await ApiService.actualizarPlanEmpresa(
                        codigoEmpresa,
                        planFinalBD,
                        limiteSucursales,
                      );

                      if (!mounted) {
                        return;
                      }

                      if (exito) {
                        nav.pop();
                        _cargarEmpresas();
                        sm.showSnackBar(
                          const SnackBar(
                            content: Text(
                              '✅ Plan actualizado. El cliente ya puede usar las nuevas funciones.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        setStateDialog(() => guardando = false);
                        sm.showSnackBar(
                          const SnackBar(
                            content: Text(
                              '❌ Error al actualizar el plan en el servidor.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('ACTUALIZAR PLAN'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoNuevaLicencia() {
    final nombreCtrl = TextEditingController();
    final codigoCtrl = TextEditingController();
    String nivelPlan = 'Básica';
    String duracionPlan = 'Permanente';
    int limiteSucursales = 1;
    bool guardando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctxDialog) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.key, color: Colors.blue),
              SizedBox(width: 10),
              Text('Generar Licencia a Cliente'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crea el ID Corto y asigna los límites operativos de la cuenta.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Comercial (Ej. Zapatos Pepe)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codigoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID Corto (Ej. PEPE)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Modalidad de Pago:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: duracionPlan,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Permanente',
                      child: Text('Pago Único (Permanente)'),
                    ),
                    DropdownMenuItem(
                      value: 'Mensual',
                      child: Text('Suscripción Mensual'),
                    ),
                    DropdownMenuItem(
                      value: 'Anual',
                      child: Text('Suscripción Anual'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setStateDialog(() => duracionPlan = val);
                    }
                  },
                ),
                const SizedBox(height: 15),
                const Text(
                  'Nivel del Plan (Límites y Funciones):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  initialValue: nivelPlan,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Básica',
                      child: Text(
                        'Básica (1 Sucursal, Funciones Limitadas)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Media',
                      child: Text(
                        'Media (Hasta 3 Sucursales)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Completa',
                      child: Text(
                        'Completa (Ilimitado, Funciones Full)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setStateDialog(() {
                        nivelPlan = val;
                        if (val == 'Básica') {
                          limiteSucursales = 1;
                        }
                        if (val == 'Media') {
                          limiteSucursales = 3;
                        }
                        if (val == 'Completa') {
                          limiteSucursales = 999;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  '⚠️ Este cliente estará limitado a crear máximo $limiteSucursales sucursal(es).',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctxDialog),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombreCtrl.text.isEmpty || codigoCtrl.text.isEmpty) {
                        return;
                      }

                      setStateDialog(() => guardando = true);

                      final nav = Navigator.of(ctxDialog);
                      final sm = ScaffoldMessenger.of(context);
                      final planFinalBD = '$duracionPlan - $nivelPlan';

                      final res = await ApiService.generarLicenciaSaaS(
                        nombreCtrl.text.trim(),
                        codigoCtrl.text.trim().toUpperCase(),
                        planFinalBD,
                        limiteSucursales,
                      );

                      if (!mounted) {
                        return;
                      }

                      if (res['exito'] == true) {
                        nav.pop();
                        _cargarEmpresas();

                        if (mounted) {
                          showDialog(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              title: const Text(
                                '¡Licencia Generada!',
                                style: TextStyle(color: Colors.green),
                              ),
                              content: SelectableText(
                                'Envíale esto a tu cliente para que active su SaaS:\n\n'
                                '🏢 EMPRESA ID: ${res['codigo_empresa']}\n'
                                '🔑 LLAVE: ${res['codigo_licencia']}\n'
                                '📦 PLAN: $planFinalBD ($limiteSucursales sucursales)',
                              ),
                              actions: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => Navigator.pop(dialogCtx),
                                  child: const Text('COPIAR Y CERRAR'),
                                ),
                              ],
                            ),
                          );
                        }
                      } else {
                        setStateDialog(() => guardando = false);
                        sm.showSnackBar(
                          SnackBar(
                            content: Text('❌ Error: ${res['error']}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              child: guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('GENERAR LICENCIA'),
            ),
          ],
        ),
      ),
    );
  }

  void _cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    List<dynamic> filtradas = _empresas.where((e) {
      final text =
          (e['nombre_empresa'].toString() + e['codigo_empresa'].toString())
              .toLowerCase();
      return text.contains(_busqueda.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text(
          'PANEL DE CONTROL SAAS',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _cerrarSesion,
            tooltip: 'Cerrar Sesión',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        onPressed: _mostrarDialogoNuevaLicencia,
        icon: const Icon(Icons.add),
        label: const Text(
          'NUEVA LICENCIA',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MODO DIOS',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
              ),
            ),
            const Text(
              'Gestiona las licencias, mejora planes de clientes y suspende servicios.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _busqueda = v),
                    decoration: const InputDecoration(
                      labelText: 'Buscar por Nombre o Código...',
                      prefixIcon: Icon(Icons.search),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 20,
                    ),
                  ),
                  onPressed: _cargarEmpresas,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ACTUALIZAR'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: ListView.builder(
                        itemCount: filtradas.length,
                        itemBuilder: (context, index) {
                          final emp = filtradas[index];
                          bool suspendida =
                              emp['suspendida'] == 1 ||
                              emp['suspendida'] == true;
                          bool pendiente =
                              emp['estado'] == 'pendiente_registro';

                          String subtitulo =
                              'Código: ${emp['codigo_empresa']} | Plan: ${emp['plan'].toString().toUpperCase()}';

                          if (pendiente) {
                            subtitulo +=
                                '\n🔑 Llave: ${emp['codigo_licencia']} (Esperando activación)';
                          } else {
                            subtitulo +=
                                '\n✅ Registrada: ${emp['fecha_registro']}';
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: suspendida
                                  ? Colors.red.shade100
                                  : (pendiente
                                        ? Colors.orange.shade100
                                        : Colors.green.shade100),
                              child: Icon(
                                Icons.business,
                                color: suspendida
                                    ? Colors.red
                                    : (pendiente
                                          ? Colors.orange
                                          : Colors.green),
                              ),
                            ),
                            title: Text(
                              emp['nombre_empresa'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(subtitulo),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: suspendida
                                        ? Colors.red
                                        : (pendiente
                                              ? Colors.orange
                                              : Colors.green),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    suspendida
                                        ? 'SUSPENDIDA'
                                        : (pendiente ? 'PENDIENTE' : 'ACTIVA'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // 🚨 BOTÓN DE UPGRADE
                                if (!pendiente && !suspendida)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.blueAccent,
                                        side: const BorderSide(
                                          color: Colors.blueAccent,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _mostrarDialogoMejorarPlan(
                                            emp['codigo_empresa'],
                                            emp['plan'].toString(),
                                          ),
                                      icon: const Icon(
                                        Icons.rocket_launch,
                                        size: 16,
                                      ),
                                      label: const Text('UPGRADE'),
                                    ),
                                  ),

                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: suspendida
                                        ? Colors.green
                                        : Colors.red,
                                    side: BorderSide(
                                      color: suspendida
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  onPressed: () => _cambiarEstado(
                                    emp['codigo_empresa'],
                                    suspendida,
                                  ),
                                  icon: Icon(
                                    suspendida
                                        ? Icons.check_circle
                                        : Icons.block,
                                    size: 16,
                                  ),
                                  label: Text(
                                    suspendida ? 'REACTIVAR' : 'SUSPENDER',
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
