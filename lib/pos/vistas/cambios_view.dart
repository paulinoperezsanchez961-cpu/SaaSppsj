import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import '../utils/escaner_utils.dart';

class CambiosView extends StatefulWidget {
  const CambiosView({super.key});
  @override
  State<CambiosView> createState() => _CambiosViewState();
}

class _CambiosViewState extends State<CambiosView> {
  final TextEditingController _entraController = TextEditingController();
  final TextEditingController _saleController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();
  final FocusNode _entraFocus = FocusNode();
  final FocusNode _saleFocus = FocusNode();

  final List<Map<String, dynamic>> _articulosEntran = [];
  final List<Map<String, dynamic>> _articulosSalen = [];
  List<dynamic> _catalogoReal = [];

  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargarCatalogoDesdeCerebro();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entraFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _entraFocus.dispose();
    _saleFocus.dispose();
    _entraController.dispose();
    _saleController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogoDesdeCerebro() async {
    try {
      // 🚨 SAAS FIX: Se añaden los Headers de Seguridad JWT
      var res = await http.get(
        Uri.parse('${ApiService.baseUrl}/pos/catalogo'),
        headers: await ApiService.getAuthHeaders(),
      );
      if (!mounted) {
        return;
      }
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        if (data['exito'] == true) {
          setState(() {
            _catalogoReal = data['productos'];
          });
        }
      }
    } catch (e) {
      debugPrint('Aviso catalogo: $e');
    }
  }

  Future<void> _registrarCambioEnMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cambiosStr = prefs.getString('caja_cambios_detalles');
    List<dynamic> cambios = cambiosStr != null ? jsonDecode(cambiosStr) : [];

    String entraTxt = _articulosEntran
        .map((e) => "${e['sku']} [${e['talla_seleccionada']}]")
        .join(", ");
    String saleTxt = _articulosSalen
        .map((e) => "${e['sku']} [${e['talla_seleccionada']}]")
        .join(", ");

    cambios.add({
      'entra': entraTxt.isEmpty ? 'Nada' : entraTxt,
      'sale': saleTxt.isEmpty ? 'Nada' : saleTxt,
      'motivo': _motivoController.text.trim(),
    });

    await prefs.setString('caja_cambios_detalles', jsonEncode(cambios));
  }

  Future<void> _escanearConCamara(bool esEntrada) async {
    try {
      var result = await BarcodeScanner.scan();
      if (result.type == ResultType.Barcode && mounted) {
        String barcodeScanRes = result.rawContent;
        if (barcodeScanRes.isNotEmpty) {
          if (esEntrada) {
            _entraController.text = barcodeScanRes;
          } else {
            _saleController.text = barcodeScanRes;
          }
          _agregarArticulo(barcodeScanRes, esEntrada);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cancelado o Error al abrir la cámara'),
            backgroundColor: Colors.orange,
          ),
        );
        if (esEntrada) {
          _entraFocus.requestFocus();
        } else {
          _saleFocus.requestFocus();
        }
      }
    }
  }

  void _mostrarSelectorDeTallasCambio(
    Map<String, dynamic> p,
    List<Map<String, dynamic>> tallasBD,
    bool esEntrada,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext contextDialog) {
        return AlertDialog(
          title: Text('Selecciona la talla de ${p['sku']}'),
          content: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: tallasBD.map((t) {
              bool agotado = t['cantidad'] <= 0 && !esEntrada;
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: agotado ? Colors.grey : Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed: agotado
                    ? null
                    : () {
                        Navigator.pop(contextDialog);
                        _ejecutarAgregarArticulo(
                          p,
                          sanitizarAlfanumerico(t['talla'].toString()),
                          tallasBD,
                          esEntrada,
                        );
                      },
                child: Text('${t['talla']} (${t['cantidad']} pz)'),
              );
            }).toList(),
          ),
        );
      },
    ).then((_) {
      if (esEntrada) {
        _entraFocus.requestFocus();
      } else {
        _saleFocus.requestFocus();
      }
    });
  }

  void _agregarArticulo(String codigo, bool esEntrada) {
    if (codigo.isEmpty) {
      if (esEntrada) {
        _entraFocus.requestFocus();
      } else {
        _saleFocus.requestFocus();
      }
      return;
    }

    final datosEscaneo = decodificarEscaneo(codigo);
    String skuLimpio = datosEscaneo['sku']!;
    String tallaLimpia = datosEscaneo['talla']!;

    final producto = _catalogoReal.where((p) {
      String dbSkuLimpio = sanitizarAlfanumerico(p["sku"].toString());
      String dbNombreLimpio = sanitizarAlfanumerico(p["nombre"].toString());
      return dbSkuLimpio == skuLimpio || dbNombreLimpio.contains(skuLimpio);
    }).toList();

    if (producto.isNotEmpty) {
      var p = producto.first;
      List<Map<String, dynamic>> tallasBD = parsearTallasBD(p['tallas']);

      if (tallaLimpia == 'UNICA' &&
          tallasBD.isNotEmpty &&
          sanitizarAlfanumerico(tallasBD[0]['talla'].toString()) != 'UNICA') {
        _mostrarSelectorDeTallasCambio(p, tallasBD, esEntrada);
        return;
      }

      _ejecutarAgregarArticulo(p, tallaLimpia, tallasBD, esEntrada);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto no encontrado'),
          backgroundColor: Colors.red,
        ),
      );
      if (esEntrada) {
        _entraController.clear();
        _entraFocus.requestFocus();
      } else {
        _saleController.clear();
        _saleFocus.requestFocus();
      }
    }
  }

  void _ejecutarAgregarArticulo(
    Map<String, dynamic> p,
    String tallaEncontradaLimpia,
    List<Map<String, dynamic>> tallasBD,
    bool esEntrada,
  ) {
    String tallaRealVisual = "ÚNICA";
    int stockDisponible = 0;

    for (var t in tallasBD) {
      if (sanitizarAlfanumerico(t['talla'].toString()) ==
          tallaEncontradaLimpia) {
        tallaRealVisual = t['talla'].toString();
        stockDisponible = t['cantidad'];
        break;
      }
    }

    if (stockDisponible == 0 && tallasBD.isEmpty) {
      stockDisponible = int.tryParse(p["stock_bodega"]?.toString() ?? '0') ?? 0;
    }

    if (!esEntrada) {
      int cantidadActual = _articulosSalen
          .where(
            (item) =>
                item['id'] == p['id'] &&
                item['talla_seleccionada'] == tallaRealVisual,
          )
          .length;
      if (stockDisponible <= cantidadActual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sin stock suficiente de la talla $tallaRealVisual'),
            backgroundColor: Colors.orange,
          ),
        );
        _saleController.clear();
        _saleFocus.requestFocus();
        return;
      }
    }

    HapticFeedback.lightImpact();

    setState(() {
      var itemNuevo = Map<String, dynamic>.from(p);
      itemNuevo['talla_seleccionada'] = tallaRealVisual;

      if (esEntrada) {
        _articulosEntran.add(itemNuevo);
        _entraController.clear();
        _entraFocus.requestFocus();
      } else {
        _articulosSalen.add(itemNuevo);
        _saleController.clear();
        _saleFocus.requestFocus();
      }
    });
  }

  Future<void> _procesarCambio() async {
    if (_articulosEntran.isEmpty ||
        _articulosSalen.isEmpty ||
        _motivoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faltan artículos o el motivo del cambio'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final sm = ScaffoldMessenger.of(context);
    setState(() {
      _procesando = true;
    });

    try {
      bool exito = await ApiService.procesarCambioFisico(
        _articulosEntran,
        _articulosSalen,
        _motivoController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      if (exito) {
        final doc = pw.Document();
        pw.MemoryImage? imageLogo;

        // 🚨 SAAAS: DESCARGA DINÁMICA DE VARIABLES LOCALES
        final prefs = await SharedPreferences.getInstance();
        final String logoUrl = prefs.getString('caja_logo_empresa') ?? '';
        final String nombreEmpresa =
            prefs.getString('caja_nombre_empresa') ?? 'MI NEGOCIO';
        final double anchoImpresora =
            prefs.getDouble('caja_ancho_impresora') ?? 80.0;

        if (logoUrl.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(logoUrl));
            if (response.statusCode == 200) {
              imageLogo = pw.MemoryImage(response.bodyBytes);
            }
          } catch (e) {
            debugPrint('Aviso Logo Cambio: $e');
          }
        }

        final now = DateTime.now();
        final fechaHora =
            '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        // 🚨 ESCALADO DINÁMICO DE FUENTES SEGÚN IMPRESORA
        double fBase = anchoImpresora == 58.0 ? 7.0 : 9.0;
        double fTitle = anchoImpresora == 58.0 ? 11.0 : 14.0;
        double fSmall = anchoImpresora == 58.0 ? 6.0 : 8.0;

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(
              anchoImpresora * PdfPageFormat.mm,
              double.infinity,
              marginAll: 5 * PdfPageFormat.mm,
            ),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  if (imageLogo != null)
                    pw.Image(
                      imageLogo,
                      width: anchoImpresora == 58.0 ? 35 : 45,
                      height: anchoImpresora == 58.0 ? 35 : 45,
                    ),
                  pw.SizedBox(height: 5),

                  pw.Text(
                    nombreEmpresa.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: fTitle,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'TICKET DE CAMBIO',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Fecha: $fechaHora',
                    style: pw.TextStyle(fontSize: fSmall),
                  ),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed),

                  pw.Text(
                    '[ ENTRA AL STOCK ]',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  ..._articulosEntran.map(
                    (item) => pw.Text(
                      '${item['sku']} - ${item['nombre']} [Talla: ${item['talla_seleccionada']}]',
                      style: pw.TextStyle(fontSize: fSmall),
                    ),
                  ),

                  pw.SizedBox(height: 10),
                  pw.Text(
                    '[ SALE AL CLIENTE ]',
                    style: pw.TextStyle(
                      fontSize: fBase,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  ..._articulosSalen.map(
                    (item) => pw.Text(
                      '${item['sku']} - ${item['nombre']} [Talla: ${item['talla_seleccionada']}]',
                      style: pw.TextStyle(fontSize: fSmall),
                    ),
                  ),

                  pw.Divider(borderStyle: pw.BorderStyle.dashed),
                  pw.Text(
                    'MOTIVO DEL CAMBIO:',
                    style: pw.TextStyle(
                      fontSize: fSmall,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _motivoController.text.trim(),
                    style: pw.TextStyle(fontSize: fSmall),
                  ),
                  pw.SizedBox(height: 15 * PdfPageFormat.mm),
                ],
              );
            },
          ),
        );

        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => doc.save(),
          name: 'Ticket_Cambio',
        );

        if (!mounted) {
          return;
        }

        await _registrarCambioEnMemoria();

        sm.showSnackBar(
          const SnackBar(
            content: Text('Cambio registrado en BD e impreso exitosamente.'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          _articulosEntran.clear();
          _articulosSalen.clear();
          _motivoController.clear();
        });
      } else {
        sm.showSnackBar(
          const SnackBar(
            content: Text(
              'Error al procesar. Verifica que haya stock de la prenda que sale.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      sm.showSnackBar(
        const SnackBar(
          content: Text('Error al procesar el cambio de red.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
      _entraFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    Widget panelEntra = Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📥 EL CLIENTE REGRESA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _entraController,
            focusNode: _entraFocus,
            decoration: InputDecoration(
              labelText: 'Escanear prenda',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              prefixIcon: const Icon(Icons.qr_code_scanner),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.blue),
                    onPressed: () => _escanearConCamara(true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () =>
                        _agregarArticulo(_entraController.text, true),
                  ),
                ],
              ),
            ),
            onSubmitted: (val) => _agregarArticulo(val, true),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _articulosEntran.length,
              itemBuilder: (context, i) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _articulosEntran[i]['nombre'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${_articulosEntran[i]['sku']} [Talla: ${_articulosEntran[i]['talla_seleccionada']}]',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 16),
                  onPressed: () {
                    setState(() {
                      _articulosEntran.removeAt(i);
                    });
                    _entraFocus.requestFocus();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Widget panelSale = Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📤 EL CLIENTE SE LLEVA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _saleController,
            focusNode: _saleFocus,
            decoration: InputDecoration(
              labelText: 'Escanear prenda',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: const Color(0xFFF9F9F9),
              prefixIcon: const Icon(Icons.qr_code_scanner),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.blue),
                    onPressed: () => _escanearConCamara(false),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () =>
                        _agregarArticulo(_saleController.text, false),
                  ),
                ],
              ),
            ),
            onSubmitted: (val) => _agregarArticulo(val, false),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _articulosSalen.length,
              itemBuilder: (context, i) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _articulosSalen[i]['nombre'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${_articulosSalen[i]['sku']} [Talla: ${_articulosSalen[i]['talla_seleccionada']}]',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 16),
                  onPressed: () {
                    setState(() {
                      _articulosSalen.removeAt(i);
                    });
                    _saleFocus.requestFocus();
                  },
                ),
              ),
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
                'LOGÍSTICA INVERSA',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 30),
              if (isMobile) ...[
                panelEntra,
                const SizedBox(height: 20),
                panelSale,
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: panelEntra),
                    const SizedBox(width: 32),
                    Expanded(child: panelSale),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo del cambio (Ej. Talla incorrecta)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFF9F9F9),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  icon: _procesando
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.print),
                  onPressed: _procesando ? null : _procesarCambio,
                  label: const Text(
                    'PROCESAR CAMBIO E IMPRIMIR',
                    style: TextStyle(
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
