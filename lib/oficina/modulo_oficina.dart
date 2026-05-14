import 'package:flutter/material.dart';

import 'vistas/dashboard_estadisticas_view.dart';
import 'vistas/inventario_oficina_view.dart';
import 'vistas/contabilidad_cortes_view.dart';
import 'vistas/promotores_vendedores_view.dart';
import 'vistas/inteligencia_artificial_view.dart';
import 'vistas/configuracion_oficina_view.dart';
import 'vistas/ventas_en_vivo_view.dart';
import 'vistas/oficina_vip_view.dart';
import 'vistas/sucursales_oficina_view.dart'; // 🏢 IMPORTACIÓN DE LA NUEVA VISTA

class ModuloOficina extends StatefulWidget {
  const ModuloOficina({super.key});

  @override
  State<ModuloOficina> createState() => _ModuloOficinaState();
}

class _ModuloOficinaState extends State<ModuloOficina> {
  int _index = 0;

  void _cambiarPestana(int nuevaPestana) {
    setState(() {
      _index = nuevaPestana;
    });
  }

  Widget _buildBotonNavegacionMovil(int index, IconData icon, String label) {
    bool isSelected = _index == index;
    return InkWell(
      onTap: () => _cambiarPestana(index),
      splashColor: Colors.white10,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white54,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = screenWidth < 800;
    bool isLargeDesktop = screenWidth >= 1100;

    final List<Widget> vistas = [
      const DashboardEstadisticasView(),
      const VentasEnVivoView(),
      const InventarioOficinaView(),
      const ContabilidadCortesView(),
      const PromotoresVendedoresView(),
      const InteligenciaArtificialView(),
      const OficinaVipView(),
      const SucursalesOficinaView(), // 🏢 VISTA DE SUCURSALES AGREGADA
      const ConfiguracionOficinaView(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),

      bottomNavigationBar: isMobile
          ? Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildBotonNavegacionMovil(
                        0,
                        Icons.analytics_outlined,
                        'DASHBOARD',
                      ),
                      _buildBotonNavegacionMovil(
                        1,
                        Icons.monitor_heart_outlined,
                        'EN VIVO',
                      ),
                      _buildBotonNavegacionMovil(
                        2,
                        Icons.inventory_2_outlined,
                        'STOCK',
                      ),
                      _buildBotonNavegacionMovil(
                        3,
                        Icons.account_balance_wallet_outlined,
                        'CORTES',
                      ),
                      _buildBotonNavegacionMovil(
                        4,
                        Icons.groups_outlined,
                        'VENDEDORES',
                      ),
                      _buildBotonNavegacionMovil(
                        5,
                        Icons.auto_awesome,
                        'CEREBRO IA',
                      ),
                      _buildBotonNavegacionMovil(
                        6,
                        Icons.workspace_premium_outlined,
                        'CLUB VIP',
                      ),
                      _buildBotonNavegacionMovil(
                        7,
                        Icons.storefront_outlined, // 🏢 ÍCONO DE SUCURSALES
                        'SUCURSALES',
                      ),
                      _buildBotonNavegacionMovil(
                        8,
                        Icons.settings_outlined,
                        'AJUSTES',
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,

      body: Row(
        children: [
          if (!isMobile)
            NavigationRail(
              extended: isLargeDesktop,
              backgroundColor: const Color(0xFF1E1E1E),
              selectedIndex: _index,
              onDestinationSelected: _cambiarPestana,
              labelType: isLargeDesktop
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.selected,
              selectedIconTheme: const IconThemeData(
                color: Colors.white,
                size: 26,
              ),
              unselectedIconTheme: const IconThemeData(
                color: Colors.white54,
                size: 24,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                letterSpacing: 1,
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.analytics_outlined),
                  label: Text('DASHBOARD'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.monitor_heart_outlined),
                  label: Text('EN VIVO'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: Text('INVENTARIO'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  label: Text('CONTABILIDAD'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.groups_outlined),
                  label: Text('VENDEDORES'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.auto_awesome),
                  label: Text('CEREBRO IA'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.workspace_premium_outlined),
                  label: Text('CLUB VIP'),
                ),
                NavigationRailDestination(
                  icon: Icon(
                    Icons.storefront_outlined,
                  ), // 🏢 NUEVO ITEM EN MENÚ
                  label: Text('SUCURSALES'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: Text('AJUSTES'),
                ),
              ],
            ),

          Expanded(
            child: IndexedStack(index: _index, children: vistas),
          ),
        ],
      ),
    );
  }
}
