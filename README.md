# UnityShaders
趣味で書いたUnityのシェーダーです。  
Shaders for Unity I wrote as a hobby.

## 使い方(How to use)
基本的にキューブなどの適当なオブジェクトに適用すればOKです。  
Basically, just apply it to an object such as a cube.

## 注意事項(Cautions)
複数のオブジェクトに適用したい場合は、オブジェクトの数だけマテリアルを作成し、すべてのマテリアルにシェーダーを適用してください。
（同じマテリアルを使うとうまく描画されないことがあります。）  
If you want to apply the shader to multiple objects, create as many materials as there are objects, and apply the shader to all of them.
(Using the same material may not render properly.)  
  
このシェーダーはDirectional Lightの方向を使用しています。  
This shader uses the directional light direction.
