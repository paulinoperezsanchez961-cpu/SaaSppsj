import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class SucursalesOficinaView extends StatefulWidget {
  const SucursalesOficinaView({super.key});

  @override
  State<SucursalesOficinaView> createState() => _SucursalesOficinaViewState();
}

class _SucursalesOficinaViewState extends State<SucursalesOficinaView> {
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _direccionCtrl = TextEditingController();
  final TextEditingController _usuarioPosCtrl = TextEditingController();
  final TextEditingController _passwordPosCtrl = TextEditingController();

  bool _guardando = false;

  Future<void> _registrarSucursal() async {
    final nombre = _nombreCtrl.text.trim();
    final dir = _direccionCtrl.text.trim();
    final user = _usuarioPosCtrl.text.trim();
    final pass = _passwordPosCtrl.text.trim();

    if (nombre.isEmpty || dir.isEmpty || user.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Todos los campos son obligatorios para abrir la sucursal.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    final sm = ScaffoldMessenger.of(context);

    final respuesta = await ApiService.crearSucursal(nombre, dir, user, pass);

    if (!mounted) return;

    if (respuesta['exito'] == true) {
      sm.showSnackBar(
        const SnackBar(
          content: Text('✅ Sucursal y Cajero registrados exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
      _nombreCtrl.clear();
      _direccionCtrl.clear();
      _usuarioPosCtrl.clear();
      _passwordPosCtrl.clear();
    } else {
      // Aquí mostraremos el error si superaron su límite de sucursales del plan
      sm.showSnackBar(
        SnackBar(
          content: Text('❌ ${respuesta['error'] ?? 'Error desconocido'}'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NUEVA SUCURSAL',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 26,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Expande tu negocio. Abre un nuevo punto de venta y asígnale credenciales para su cajero.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 32),

              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 800),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SECCIÓN 1: DATOS FÍSICOS
                        const Row(
                          children: [
                            Icon(Icons.storefront, color: Colors.blueAccent),
                            SizedBox(width: 10),
                            Text(
                              '1. UBICACIÓN FÍSICA',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        TextField(
                          controller: _nombreCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'Nombre de la Sucursal (Ej. Plaza Centro, Norte)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.badge_outlined),
                            filled: true,
                            fillColor: Color(0xFFFBFBFB),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _direccionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dirección Completa',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on_outlined),
                            filled: true,
                            fillColor: Color(0xFFFBFBFB),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // SECCIÓN 2: ACCESO CAJERO
                        const Row(
                          children: [
                            Icon(Icons.point_of_sale, color: Colors.green),
                            SizedBox(width: 10),
                            Text(
                              '2. CREDENCIALES DE CAJA (PUNTO DE VENTA)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        const Text(
                          'El cajero de esta sucursal usará estos datos para entrar a cobrar. El sistema lo aislará automáticamente para que no vea la oficina.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),

                        isMobile
                            ? Column(
                                children: [
                                  TextField(
                                    controller: _usuarioPosCtrl,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Usuario del Cajero (Ej: caja_centro)',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _passwordPosCtrl,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Contraseña de la Caja',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.lock_outline),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _usuarioPosCtrl,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Usuario del Cajero (Ej: caja_centro)',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.person_outline),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(
                                      controller: _passwordPosCtrl,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Contraseña de la Caja',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.lock_outline),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                        const SizedBox(height: 40),

                        // BOTÓN DE GUARDADO
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
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
                                : const Icon(Icons.add_business),
                            label: Text(
                              _guardando
                                  ? 'REGISTRANDO...'
                                  : 'ABRIR SUCURSAL Y CREAR ACCESO',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            onPressed: _guardando ? null : _registrarSucursal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
