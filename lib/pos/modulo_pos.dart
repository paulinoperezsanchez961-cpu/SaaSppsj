import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚨 IMPORTACIONES DE TUS VISTAS SEPARADAS
import 'vistas/terminal_cobro_view.dart';
import 'vistas/cambios_view.dart';
import 'vistas/registro_gastos_view.dart';
import 'vistas/apartados_view.dart';
import 'vistas/boveda_qr_view.dart';
import 'vistas/envios_web_view.dart';
import 'vistas/inventario_stock_view.dart';
import 'vistas/promotores_vendedores_view.dart';
import 'vistas/registro_vip_view.dart'; // 👑 IMPORTACIÓN DE LA NUEVA VISTA VIP

// ============================================================================
// MÓDULO MAESTRO: PUNTO DE VENTA (POS)
// ============================================================================
class ModuloPOS extends StatefulWidget {
  const ModuloPOS({super.key});
  @override
  State<ModuloPOS> createState() => _ModuloPOSState();
}

class _ModuloPOSState extends State<ModuloPOS> {
  int _index = 0;
  double ventasDelDia = 0.0;
  double gastosDelDia = 0.0;

  @override
  void initState() {
    super.initState();
    _cargarTotalesMemoria();
  }

  Future<void> _cargarTotalesMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ventasDelDia = prefs.getDouble('caja_ventas') ?? 0.0;
      gastosDelDia = prefs.getDouble('caja_gastos') ?? 0.0;
    });
  }

  void _actualizarTotalesDia({double? venta, double? gasto}) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (venta != null) ventasDelDia += venta;
      if (gasto != null) gastosDelDia += gasto;
    });
    await prefs.setDouble('caja_ventas', ventasDelDia);
    await prefs.setDouble('caja_gastos', gastosDelDia);
  }

  void _cerrarCajaYLimpiar() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('caja_ventas');
    await prefs.remove('caja_gastos');
    await prefs.remove('caja_carrito');
    await prefs.remove('caja_lista_gastos');
    await prefs.remove('caja_ventas_detalles');
    await prefs.remove('caja_apartados_detalles');
    await prefs.remove('caja_cambios_detalles');

    setState(() {
      ventasDelDia = 0.0;
      gastosDelDia = 0.0;
    });
  }

  void _cambiarPestana(int nuevaPestana) {
    setState(() {
      _index = nuevaPestana;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              currentIndex: _index,
              onTap: _cambiarPestana,
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFFF9F9F9),
              selectedItemColor: Colors.black,
              unselectedItemColor: Colors.grey,
              showUnselectedLabels: true,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 8,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 8),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.point_of_sale_outlined, size: 20),
                  label: 'CAJA',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.sync_alt_outlined, size: 20),
                  label: 'CAMBIOS',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long_outlined, size: 20),
                  label: 'GASTOS',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bookmark_border, size: 20),
                  label: 'APARTADOS',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.qr_code_scanner_outlined, size: 20),
                  label: 'QR',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.local_shipping_outlined, size: 20),
                  label: 'ENVÍOS',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.inventory_2_outlined, size: 20),
                  label: 'STOCK',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline, size: 20),
                  label: 'VENDEDORES',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.workspace_premium_outlined, size: 20),
                  label: 'VIP',
                ), // 👑 NUEVO ÍTEM COMPACTO
              ],
            )
          : null,
      body: Row(
        children: [
          if (!isMobile)
            NavigationRail(
              backgroundColor: const Color(0xFFF9F9F9),
              selectedIndex: _index,
              onDestinationSelected: _cambiarPestana,
              labelType: NavigationRailLabelType.selected,
              selectedIconTheme: const IconThemeData(color: Colors.black),
              unselectedIconTheme: const IconThemeData(color: Colors.grey),
              selectedLabelTextStyle: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.point_of_sale_outlined),
                  label: Text('CAJA'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.sync_alt_outlined),
                  label: Text('CAMBIOS'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  label: Text('GASTOS'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bookmark_border),
                  label: Text('APARTADOS'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  label: Text('BÓVEDA QR'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('ENVÍOS WEB'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: Text('STOCK'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people_outline),
                  label: Text('VENDEDORES'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.workspace_premium_outlined),
                  label: Text('VIP'),
                ), // 👑 NUEVO ÍTEM COMPACTO
              ],
            ),
          if (!isMobile)
            const VerticalDivider(
              thickness: 1,
              width: 1,
              color: Colors.black12,
            ),
          Expanded(
            // 🚨 OPTIMIZACIÓN CRÍTICA: IndexedStack preserva el estado de las pantallas.
            // Esto evita que se borre el carrito si la cajera cambia de pestaña para revisar algo.
            child: IndexedStack(
              index: _index,
              children: [
                TerminalCobroView(
                  onVentaExitosa: (monto) =>
                      _actualizarTotalesDia(venta: monto),
                  onCerrarCaja: _cerrarCajaYLimpiar,
                  ventasTotales: ventasDelDia,
                  gastosTotales: gastosDelDia,
                ),
                const CambiosView(),
                RegistroGastosView(
                  onGastoRegistrado: (monto) =>
                      _actualizarTotalesDia(gasto: monto),
                ),
                ApartadosView(
                  onVentaExitosa: (monto) =>
                      _actualizarTotalesDia(venta: monto),
                ),
                BovedaQRView(onCerrar: () => _cambiarPestana(0)),
                const EnviosWebView(),
                const InventarioStockView(),
                PromotoresVendedoresView(
                  onGastoRegistrado: (monto) =>
                      _actualizarTotalesDia(gasto: monto),
                ),
                const RegistroVipView(), // 👑 NUEVA VISTA AGREGADA A LA PILA
              ],
            ),
          ),
        ],
      ),
    );
  }
}
