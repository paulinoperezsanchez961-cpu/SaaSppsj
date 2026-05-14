import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../services/api_service.dart';
import '../utils/escaner_utils.dart';

class InventarioStockView extends StatefulWidget {
  const InventarioStockView({super.key});

  @override
  State<InventarioStockView> createState() => _InventarioStockViewState();
}

class _InventarioStockViewState extends State<InventarioStockView> {
  List<dynamic> _productosReales = [];
  List<dynamic> _productosFiltrados = [];
  final TextEditingController _buscadorController = TextEditingController();

  bool _cargando = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final datos = await ApiService.obtenerInventario();
      if (!mounted) {
        return;
      }
      setState(() {
        _productosReales = datos;
        _productosFiltrados = datos;
        _buscadorController.clear();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _cargando = false);
    }
  }

  void _filtrarProductos(String query) {
    if (query.isEmpty) {
      setState(() => _productosFiltrados = _productosReales);
      return;
    }

    final q = query.toLowerCase();
    setState(() {
      _productosFiltrados = _productosReales.where((p) {
        final sku = (p['sku'] ?? '').toString().toLowerCase();
        final nombre = (p['nombre'] ?? '').toString().toLowerCase();
        return sku.contains(q) || nombre.contains(q);
      }).toList();
    });
  }

  Future<void> _actualizarFotoProducto(int idProducto) async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de la Galería'),
                onTap: () {
                  Navigator.of(context).pop();
                  _procesarSubidaFoto(idProducto, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Tomar Foto con Cámara'),
                onTap: () {
                  Navigator.of(context).pop();
                  _procesarSubidaFoto(idProducto, ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _procesarSubidaFoto(int idProducto, ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (image == null || !mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subiendo nueva foto...'),
          duration: Duration(seconds: 1),
        ),
      );

      final bytes = await image.readAsBytes();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/pos/actualizar-foto/$idProducto'),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'foto',
          bytes,
          filename: image.name,
          contentType: MediaType('image', image.name.split('.').last),
        ),
      );

      var response = await http.Response.fromStream(await request.send());

      // 🚨 Guardia de seguridad antes del contexto
      if (!mounted) {
        return;
      }

      if (response.statusCode == 200) {
        _cargarDatos();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto actualizada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al guardar en el servidor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('Aviso foto: $e');
    }
  }

  void _solicitarClaveParaEliminar(Map<String, dynamic> prod) {
    TextEditingController claveController = TextEditingController();
    bool verificando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (contextDialog) {
        return StatefulBuilder(
          builder: (contextBuilder, setStateDialog) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red),
                  SizedBox(width: 10),
                  Text(
                    'Eliminar Producto',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Se eliminará por completo "${prod['nombre']}" del sistema. Requiere contraseña de Administrador.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: claveController,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña Maestra',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(contextDialog),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: verificando
                      ? null
                      : () async {
                          if (claveController.text.trim().isEmpty) {
                            return;
                          }
                          setStateDialog(() => verificando = true);

                          bool autorizado =
                              await ApiService.verificarClaveAdmin(
                                claveController.text.trim(),
                              );

                          if (!mounted || !contextDialog.mounted) {
                            return;
                          }

                          setStateDialog(() => verificando = false);

                          if (autorizado) {
                            Navigator.pop(contextDialog);

                            bool exito = await ApiService.eliminarProducto(
                              prod['id'],
                            );

                            if (!mounted) {
                              return;
                            }

                            if (exito) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Producto eliminado'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _cargarDatos();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('❌ Error al eliminar'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('❌ Contraseña Incorrecta'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  child: verificando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('ELIMINAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 🚨 LECTOR DE TALLAS MULTI-SUCURSAL
  List<Map<String, dynamic>> _parsearTallasMultiSucursal(
    dynamic tallasRawData,
  ) {
    List<dynamic> tallasRaw = [];
    if (tallasRawData != null) {
      if (tallasRawData is String) {
        try {
          tallasRaw = jsonDecode(tallasRawData);
        } catch (e) {
          debugPrint('Aviso JSON: $e');
        }
      } else if (tallasRawData is List) {
        tallasRaw = tallasRawData;
      }
    }

    return tallasRaw.map((e) {
      if (e is Map) {
        return {
          'talla': (e['talla'] ?? e['nombre'] ?? 'ÚNICA')
              .toString()
              .trim()
              .toUpperCase(),
          'cantidad':
              int.tryParse(
                e['cantidad']?.toString() ?? e['stock']?.toString() ?? '0',
              ) ??
              0,
          'sucursal': (e['sucursal'] ?? 'BODEGA CENTRAL')
              .toString()
              .toUpperCase(),
        };
      } else {
        return {
          'talla': e.toString().trim().toUpperCase(),
          'cantidad': 1,
          'sucursal': 'BODEGA CENTRAL',
        };
      }
    }).toList();
  }

  void _abrirGestorResurtido(Map<String, dynamic> prod) {
    List<Map<String, dynamic>> tallasEnEdicion = _parsearTallasMultiSucursal(
      prod['tallas'],
    );
    List<Map<String, dynamic>> tallasAgregadasParaImprimir = [];

    TextEditingController nuevaSucursalCtrl = TextEditingController(
      text: 'BODEGA CENTRAL',
    );
    TextEditingController nuevaTallaCtrl = TextEditingController();
    TextEditingController nuevaCantCtrl = TextEditingController();
    bool guardando = false;

    showDialog(
      context: context,
      builder: (contextDialog) {
        return StatefulBuilder(
          builder: (contextBuilder, setStateDialog) {
            int stockTotalCalculado = tallasEnEdicion.fold(
              0,
              (sum, item) => sum + (item['cantidad'] as int),
            );

            return AlertDialog(
              title: Text(
                'Ajuste de Stock: ${prod['sku']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: nuevaSucursalCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Sucursal (Ej: Tlaxcala, Norte...)',
                                isDense: true,
                                border: OutlineInputBorder(),
                                fillColor: Colors.white,
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: nuevaTallaCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Talla',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      fillColor: Colors.white,
                                      filled: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 1,
                                  child: TextField(
                                    controller: nuevaCantCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Pzs',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      fillColor: Colors.white,
                                      filled: true,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle,
                                    color: Colors.green,
                                    size: 30,
                                  ),
                                  onPressed: () {
                                    String suc = nuevaSucursalCtrl.text
                                        .trim()
                                        .toUpperCase();
                                    String t = nuevaTallaCtrl.text
                                        .trim()
                                        .toUpperCase();
                                    int c =
                                        int.tryParse(nuevaCantCtrl.text) ?? 0;

                                    if (t.isNotEmpty &&
                                        c > 0 &&
                                        suc.isNotEmpty) {
                                      setStateDialog(() {
                                        int idx = tallasEnEdicion.indexWhere(
                                          (element) =>
                                              element['talla'] == t &&
                                              element['sucursal'] == suc,
                                        );
                                        if (idx != -1) {
                                          tallasEnEdicion[idx]['cantidad'] =
                                              (tallasEnEdicion[idx]['cantidad']
                                                  as int) +
                                              c;
                                        } else {
                                          tallasEnEdicion.add({
                                            'talla': t,
                                            'cantidad': c,
                                            'sucursal': suc,
                                          });
                                        }

                                        int idxPrint =
                                            tallasAgregadasParaImprimir
                                                .indexWhere(
                                                  (element) =>
                                                      element['talla'] == t,
                                                );
                                        if (idxPrint != -1) {
                                          tallasAgregadasParaImprimir[idxPrint]['cantidad'] =
                                              (tallasAgregadasParaImprimir[idxPrint]['cantidad']
                                                  as int) +
                                              c;
                                        } else {
                                          tallasAgregadasParaImprimir.add({
                                            'talla': t,
                                            'cantidad': c,
                                          });
                                        }

                                        nuevaTallaCtrl.clear();
                                        nuevaCantCtrl.clear();
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Divider(),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: tallasEnEdicion.length,
                          itemBuilder: (c, i) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '[${tallasEnEdicion[i]['sucursal']}] Talla: ${tallasEnEdicion[i]['talla']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 20,
                                  ),
                                  onPressed: () => setStateDialog(() {
                                    if (tallasEnEdicion[i]['cantidad'] > 0) {
                                      tallasEnEdicion[i]['cantidad']--;
                                    }
                                  }),
                                ),
                                SizedBox(
                                  width: 30,
                                  child: Center(
                                    child: Text(
                                      '${tallasEnEdicion[i]['cantidad']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 20,
                                  ),
                                  onPressed: () => setStateDialog(() {
                                    tallasEnEdicion[i]['cantidad']++;
                                    String t = tallasEnEdicion[i]['talla'];
                                    int idxPrint = tallasAgregadasParaImprimir
                                        .indexWhere(
                                          (element) => element['talla'] == t,
                                        );
                                    if (idxPrint != -1) {
                                      tallasAgregadasParaImprimir[idxPrint]['cantidad']++;
                                    } else {
                                      tallasAgregadasParaImprimir.add({
                                        'talla': t,
                                        'cantidad': 1,
                                      });
                                    }
                                  }),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 20,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => setStateDialog(
                                    () => tallasEnEdicion.removeAt(i),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'STOCK GLOBAL CALCULADO:',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$stockTotalCalculado PZS',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.blue,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(contextDialog),
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
                          setStateDialog(() => guardando = true);
                          final nav = Navigator.of(contextDialog);
                          final sm = ScaffoldMessenger.of(context);

                          bool exito = await ApiService.resurtirProducto(
                            prod['id'],
                            tallasEnEdicion,
                            stockTotalCalculado,
                          );

                          if (!contextDialog.mounted) {
                            return;
                          }
                          nav.pop();

                          if (!mounted) {
                            return;
                          }

                          if (exito) {
                            setState(() {
                              prod['tallas'] = jsonEncode(tallasEnEdicion);
                              prod['stock_bodega'] = stockTotalCalculado;
                            });

                            sm.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Distribución de Stock actualizada.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            if (tallasAgregadasParaImprimir.isNotEmpty) {
                              _imprimirEtiquetasNuevas(
                                prod,
                                tallasAgregadasParaImprimir,
                              );
                            }
                          } else {
                            setStateDialog(() => guardando = false);
                            sm.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Error al sincronizar con el servidor.',
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
                      : const Text('GUARDAR E IMPRIMIR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _imprimirEtiquetasNuevas(
    Map<String, dynamic> prod,
    List<Map<String, dynamic>> tallasNuevas,
  ) async {
    String corteLote = prod['sku'];
    String nombreModelo = prod['nombre'] ?? '';
    double precioProducto =
        double.tryParse(prod['precio_venta']?.toString() ?? '0') ?? 0.0;

    int totalEtiquetas = tallasNuevas.fold(
      0,
      (sum, item) => sum + (item['cantidad'] as int),
    );
    if (totalEtiquetas == 0) {
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enviando $totalEtiquetas nuevas etiquetas...'),
          duration: const Duration(seconds: 2),
        ),
      );

      final doc = pw.Document();
      final formatNuevo = const PdfPageFormat(
        51.5 * PdfPageFormat.mm,
        25.4 * PdfPageFormat.mm,
        marginAll: 0,
      );

      for (var item in tallasNuevas) {
        for (int i = 0; i < item['cantidad']; i++) {
          String dataQrUnico = "$corteLote TALLA ${item['talla']}";
          doc.addPage(
            pw.Page(
              pageFormat: formatNuevo,
              build: (pw.Context context) {
                return pw.Container(
                  width: 51.5 * PdfPageFormat.mm,
                  height: 25.4 * PdfPageFormat.mm,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 3 * PdfPageFormat.mm,
                    vertical: 2 * PdfPageFormat.mm,
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(
                        color: PdfColors.black,
                        barcode: pw.Barcode.qrCode(),
                        data: dataQrUnico,
                        width: 18 * PdfPageFormat.mm,
                        height: 18 * PdfPageFormat.mm,
                      ),
                      pw.SizedBox(width: 3 * PdfPageFormat.mm),
                      pw.Expanded(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              nombreModelo.toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 6,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              maxLines: 1,
                            ),
                            pw.SizedBox(height: 1 * PdfPageFormat.mm),
                            pw.Text(
                              corteLote,
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'Talla: ${item['talla']}',
                              style: pw.TextStyle(fontSize: 7),
                            ),
                            pw.Text(
                              '\$${precioProducto.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }
      }
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Resurtido_$corteLote',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impresión completada'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al imprimir: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _reimprimirEtiquetas(Map<String, dynamic> prod) async {
    String corteLote = prod['sku'];
    String nombreModelo = prod['nombre'] ?? '';
    double precioProducto =
        double.tryParse(prod['precio_venta']?.toString() ?? '0') ?? 0.0;

    List<Map<String, dynamic>> tallasBD = _parsearTallasMultiSucursal(
      prod['tallas'],
    );

    int totalEtiquetas = tallasBD.fold(
      0,
      (sum, item) => sum + (item['cantidad'] as int),
    );
    if (totalEtiquetas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este producto tiene 0 piezas en inventario.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Generando $totalEtiquetas etiquetas...'),
          duration: const Duration(seconds: 1),
        ),
      );
      final doc = pw.Document();
      final formatNuevo = const PdfPageFormat(
        51.5 * PdfPageFormat.mm,
        25.4 * PdfPageFormat.mm,
        marginAll: 0,
      );

      for (var item in tallasBD) {
        for (int i = 0; i < item['cantidad']; i++) {
          String dataQrUnico = "$corteLote TALLA ${item['talla']}";
          doc.addPage(
            pw.Page(
              pageFormat: formatNuevo,
              build: (pw.Context context) {
                return pw.Container(
                  width: 51.5 * PdfPageFormat.mm,
                  height: 25.4 * PdfPageFormat.mm,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 3 * PdfPageFormat.mm,
                    vertical: 2 * PdfPageFormat.mm,
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.start,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(
                        color: PdfColors.black,
                        barcode: pw.Barcode.qrCode(),
                        data: dataQrUnico,
                        width: 18 * PdfPageFormat.mm,
                        height: 18 * PdfPageFormat.mm,
                      ),
                      pw.SizedBox(width: 3 * PdfPageFormat.mm),
                      pw.Expanded(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              nombreModelo.toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 6,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              maxLines: 1,
                            ),
                            pw.SizedBox(height: 1 * PdfPageFormat.mm),
                            pw.Text(
                              corteLote,
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'Talla: ${item['talla']}',
                              style: pw.TextStyle(fontSize: 7),
                            ),
                            pw.Text(
                              '\$${precioProducto.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }
      }
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Reimpresion_$corteLote',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impresión enviada'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al imprimir: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _verImagen(String url, String modelo) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(url),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  modelo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚨 UI: AGRUPACIÓN VISUAL POR SUCURSALES EN EL POS
  Widget _construirDesglosePorSucursal(dynamic tallasRaw) {
    List<Map<String, dynamic>> tallas = _parsearTallasMultiSucursal(tallasRaw);
    if (tallas.isEmpty) {
      return const Text(
        "Sin desglose de stock",
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }

    Map<String, int> totalesPorSucursal = {};
    Map<String, List<String>> detallesPorSucursal = {};

    for (var t in tallas) {
      String suc = t['sucursal'] ?? 'BODEGA CENTRAL';
      totalesPorSucursal[suc] =
          (totalesPorSucursal[suc] ?? 0) + (t['cantidad'] as int);

      if (detallesPorSucursal[suc] == null) {
        detallesPorSucursal[suc] = [];
      }
      detallesPorSucursal[suc]!.add("${t['talla']}: ${t['cantidad']}");
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: totalesPorSucursal.keys.map((suc) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              children: [
                TextSpan(
                  text: '📍 $suc: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
                TextSpan(text: detallesPorSucursal[suc]!.join("  |  ")),
                TextSpan(
                  text: '  (Total: ${totalesPorSucursal[suc]} pzs)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
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
            const Text(
              'INVENTARIO OMNICANAL',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w300,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _buscadorController,
              onChanged: _filtrarProductos,
              decoration: InputDecoration(
                labelText: 'Buscar por SKU o Nombre...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscadorController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscadorController.clear();
                          _filtrarProductos('');
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: _cargando
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : _productosFiltrados.isEmpty
                  ? const Center(
                      child: Text(
                        "No hay productos",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarDatos,
                      color: Colors.black,
                      child: ListView.separated(
                        itemCount: _productosFiltrados.length,
                        separatorBuilder: (c, i) => const Divider(),
                        itemBuilder: (context, index) {
                          final prod = _productosFiltrados[index];
                          String fotoUrl = sanearImagen(
                            prod['url_foto_principal'],
                          );

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(color: Colors.black12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        _verImagen(fotoUrl, prod['sku']),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        fotoUrl,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          width: 80,
                                          height: 80,
                                          color: Colors.grey.shade200,
                                          child: const Icon(
                                            Icons.image_not_supported,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prod['nombre'] ?? 'Prenda',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          'SKU: ${prod['sku']}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 10),

                                        // 🚨 DESGLOSE VISUAL DE STOCK POR SUCURSAL
                                        _construirDesglosePorSucursal(
                                          prod['tallas'],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Stock Global: ${prod['stock_bodega']}',
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                        ),
                                        icon: const Icon(Icons.print, size: 14),
                                        label: const Text(
                                          'REIMPRIMIR',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        onPressed: () =>
                                            _reimprimirEtiquetas(prod),
                                      ),
                                      const SizedBox(height: 5),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.green,
                                          side: const BorderSide(
                                            color: Colors.green,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.add_box,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'AJUSTE STOCK',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        onPressed: () =>
                                            _abrirGestorResurtido(prod),
                                      ),
                                      const SizedBox(height: 5),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.camera_alt,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'CAMBIAR FOTO',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        onPressed: () =>
                                            _actualizarFotoProducto(prod['id']),
                                      ),
                                      const SizedBox(height: 5),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(
                                            color: Colors.red,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.delete,
                                          size: 14,
                                        ),
                                        label: const Text(
                                          'ELIMINAR',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        onPressed: () =>
                                            _solicitarClaveParaEliminar(prod),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
