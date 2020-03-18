import 'package:flutter/material.dart';


abstract class ConfigPage {
  final GlobalKey<FormState> key;
  bool _seen = false;
  bool _current = false;
  bool get seen => _seen;
  bool get current => _current;
  set current(bool status) {
    if (_current)
      _seen = true;
    _current = status;
  }

  ConfigPage([GlobalKey<FormState> key]):this.key = key ?? GlobalKey<FormState>();

  Widget _buildPage();

  Form build(){
    return Form(key: key, child: _buildPage(),);
  }
}