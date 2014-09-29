import 'package:polymer/polymer.dart';
import 'dart:html';

@CustomTag('iz-output')
class IzOutput extends PolymerElement {

  @published String filename="Error! Filename wasnt loaded...";
  @published int progress=0;
  @published String statut;
  

  
  IzOutput.created() : super.created(){  
  }
  
  void remove(){
    dispatchEvent(new CustomEvent('remove',detail: this.id ));
  }
  
}