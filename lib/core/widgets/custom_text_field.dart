import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? maxLength;
  final String? errorText;
  final String? helperText;
  final bool readOnly;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onTap;

  const CustomTextField({
    super.key,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.controller,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.maxLength,
    this.errorText,
    this.helperText,
    this.readOnly = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          maxLines: obscureText ? 1 : maxLines,
          maxLength: maxLength,
          readOnly: readOnly,
          autofocus: autofocus,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            counterText: '',
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
