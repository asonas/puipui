# Puipui

macOSメニューバーアプリです。CPU使用率、メモリ使用率と圧力、主要ネットワークインターフェースの受信・送信速度を1秒ごとに取得し、直近5分をグラフ表示します。ディスク空き容量は60秒ごとに更新します。Mole 1.53系のdry-runを手動または60分ごとに実行し、整理可能な概算容量を表示します。左側にGhosttyの埋め込み端末を開けます。CLEANはクリーンアップコマンドの入力までを行い、実行はユーザーのEnter操作に委ねます。未取得値は `—` で表示します。

## ビルドと起動

Swift 6対応のXcodeを選択した環境で実行します。

```sh
sh scripts/build-app.sh
open build/Puipui.app
```

Finderから `build/Puipui.app` を開くこともできます。チーム `QYP65434UW` のApple Development証明書で署名します。証明書と秘密鍵がキーチェーンに必要です。配布用の公証はしていません。

フォルダアクセス許可を更新後も引き継ぐため、同じBundle IDと開発用署名を継続して使います。証明書が見つからない場合はビルドを失敗させ、アドホック署名には切り替えません。従来のアドホック署名から移行した直後は、アクセス許可を再度求められることがあります。

## 操作

- メニューバーの `PUI` をクリックすると、直下にパネルを表示します。Dockには表示しません。
- 上端にカーソルを置くとハンドルが現れます。下へドラッグし、マウスを離すと上にウィンドウボタン領域が伸びます。「視差効果を減らす」が有効な場合はアニメーションしません。
- ウィンドウボタン用の32ptは独立時だけ追加します。通常表示では内容に合わせた高さになります。
- 独立ウィンドウを閉じた後、`PUI` をクリックするとパネルとして再表示します。
- `SCAN` は `mo clean --dry-run` を開始します。クリーンアップ対象は削除しませんが、Moleの候補一覧と操作ログは更新します。
- `CLEAN` は新しいターミナルに `mo clean` を入力します。Enterは送信しません。実行する場合だけ自分でEnterを押してください。Moleは実行開始後に削除を行うため、対象の確認には先に `SCAN`（dry-run）を利用してください。既存ターミナルがある場合は入力せず、先に `CLOSE` で閉じるよう案内します。
- `QUIT` でアプリを終了します。
- `TERMINAL` で左側にGhosttyターミナルを開きます。同じボタンで隠してもセッションは残り、`CLOSE` でシェルを終了します。アプリ終了時もシェルを終了・回収します。
- ターミナルはホームディレクトリで、macOSアカウントに設定されたログインシェルを `-l -i` 付きで起動します。zshなら `.zprofile`・`.zshrc` など通常の設定を読み込みます。コマンドの終了は監視していません。空き容量は60秒ごとに更新され、整理可能容量の再集計には `SCAN` を使います。
- ターミナルは本体の左端から0.28秒で引き出され、0.20秒で収納されます。文字サイズは変えず、表示領域だけを広げます。「視差効果を減らす」設定では0.10秒のフェードだけになります。

CPU・MEMのグラフは0〜100%の固定軸です。NETは受信と送信の合計で、上限を表示中の最大値に合わせた切りのよい値へ調整します。上下限と中央の補助線を表示します。

## 検証

```sh
build/Puipui.app/Contents/MacOS/Puipui --check-window
build/Puipui.app/Contents/MacOS/Puipui --check-metrics
build/Puipui.app/Contents/MacOS/Puipui --check-storage
build/Puipui.app/Contents/MacOS/Puipui --check-terminal
build/Puipui.app/Contents/MacOS/Puipui --check-window --animate-window
```

ウィンドウ操作、CPU・メモリ・主要ネットワークインターフェース、ディスク容量・Mole互換性・プレビュー形式を検証します。

回帰テストはXcodeのSwift Testingで実行します。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`--check-scan` は実際のdry-runを1回実行し、新しい結果の検証と集計まで確認します。Moleの候補一覧と操作ログを更新するため、通常の読み取り検査とは別に実行します。
