import 'package:intl/intl.dart';

import '../storage/session_store.dart';

/// Every monetary column the API returns is stored in this currency and
/// converted for display only.
const kBaseCurrency = 'INR';
const kDefaultCurrency = 'AED';

double convertFromBase(double amount, String? to, Map<String, double> rates) {
  final target = (to ?? kDefaultCurrency).toUpperCase();
  if (target == kBaseCurrency) return amount;
  final from = rates[kBaseCurrency];
  final into = rates[target];
  // Without both rates the amount passes through unconverted, as on the web —
  // showing a wrong number would be worse than showing an unconverted one.
  if (from == null || into == null || into == 0) return amount;
  return amount * from / into;
}

String formatCurrencyFromBase(double? amount, Permissions permissions) {
  final code = (permissions.currencyType ?? kDefaultCurrency).toUpperCase();
  final value = convertFromBase(
    amount ?? 0,
    code,
    permissions.currencyRates,
  );
  return NumberFormat.simpleCurrency(name: code).format(value);
}
