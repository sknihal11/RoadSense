import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:io';

void main() {
  test('Inspect TFLite models', () {
    final tusharFile = File('C:/Users/naffu/.gemini/antigravity-ide/brain/c2fbe8f5-e6b6-4347-8d01-c71c4f83f9f9/scratch/tushar.tflite');
    final lordpatilFile = File('C:/Users/naffu/.gemini/antigravity-ide/brain/c2fbe8f5-e6b6-4347-8d01-c71c4f83f9f9/scratch/lordpatil.tflite');
    
    if (tusharFile.existsSync()) {
      print('--- TUSHAR MODEL ---');
      try {
        final interpreter = Interpreter.fromFile(tusharFile);
        print('Inputs count: ${interpreter.getInputTensors().length}');
        for (int i = 0; i < interpreter.getInputTensors().length; i++) {
          final t = interpreter.getInputTensor(i);
          print('Input $i: name=${t.name}, shape=${t.shape}, type=${t.type}');
        }
        print('Outputs count: ${interpreter.getOutputTensors().length}');
        for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
          final t = interpreter.getOutputTensor(i);
          print('Output $i: name=${t.name}, shape=${t.shape}, type=${t.type}');
        }
        interpreter.close();
      } catch (e) {
        print('Error inspecting Tushar model: $e');
      }
    }
    
    if (lordpatilFile.existsSync()) {
      print('--- LORDPATIL MODEL ---');
      try {
        final interpreter = Interpreter.fromFile(lordpatilFile);
        print('Inputs count: ${interpreter.getInputTensors().length}');
        for (int i = 0; i < interpreter.getInputTensors().length; i++) {
          final t = interpreter.getInputTensor(i);
          print('Input $i: name=${t.name}, shape=${t.shape}, type=${t.type}');
        }
        print('Outputs count: ${interpreter.getOutputTensors().length}');
        for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
          final t = interpreter.getOutputTensor(i);
          print('Output $i: name=${t.name}, shape=${t.shape}, type=${t.type}');
        }
        interpreter.close();
      } catch (e) {
        print('Error inspecting LordPatil model: $e');
      }
    }
  });
}
