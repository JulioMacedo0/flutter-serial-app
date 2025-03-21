import 'package:barcode_app/app_version_widget.dart';
import 'package:flutter/material.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Cabeçalho estilizado
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Center(
              child: Text(
                'Menu de Operações',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Lista de botões
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  _buildMenuButton(
                    context,
                    icon: Icons.check_circle,
                    text: "Finalizar Ordem de Carga",
                    color: Colors.green,
                    onPressed: () {
                      // Lógica para finalizar a ordem de carga
                    },
                  ),
                  SizedBox(height: 12),
                  _buildMenuButton(
                    context,
                    icon: Icons.pause_circle_filled,
                    text: "Pausar Ordem de Carga",
                    color: Colors.orange,
                    onPressed: () {
                      // Lógica para pausar a ordem de carga
                    },
                  ),
                  Spacer(),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppVersionWidget(),
          ),
        ],
      ),
    );
  }

  // Método para criar botões estilizados do menu
  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          text,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: 14),
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
