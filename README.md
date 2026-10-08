# GMornCsv

## Overview

Godot Editorの中央ビューでCSVを表示・編集するアドオンです。

## Requirements

- Godot 4.7以降

## Features

- CSVを選択して表で表示。行番号とExcel形式の列見出し。
- ダブルクリックで編集し、変更セルを強調。列幅・行高を確定時に再計算。
- 行番号・列見出しの右クリックで行列を追加・削除。
- Shiftスクロールで横移動、Ctrl／Command＋Z・Y・SでUndo・Redo・保存。
- Enterで確定、Shift＋Enterで改行、Escで取消。
- 保存／破棄、未保存確認、外部変更の上書き拒否。同じフォルダの一時ファイルから置換。
- 引用符・カンマ・セル内改行・末尾空欄・幅の違う行を保持。

## Usage

1. プロジェクトへ追加します。

   ```sh
   git submodule add https://github.com/TsukumiStudio/GMornCsv.git addons/gmorn_csv
   ```

2. Project Settings → PluginsでGMornCsvを有効にします。
3. FileSystemでCSVを選択し、セルをダブルクリックして編集します。
4. 「変更を保存」でファイルに反映します。「変更を破棄」で保存前へ戻します。

列幅は80〜360pxです。長い値はツールチップで全文を表示します。保存まで元ファイルは変更しません。保存後もUndoできますが、ファイル切替・破棄・再読込では履歴をクリアします。Editor専用で本編には組み込みません。

単体検証は `./verify.sh`。使い捨てプロジェクトとデータでヘッドレス検証します。

## License

[Unlicense](UNLICENSE)
