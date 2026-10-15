# Puipui

macOSメニューバーアプリです。CPUのUser・System別使用率、メモリ使用率と圧力、主要ネットワークインターフェースの受信・送信速度を1秒ごとに取得し、直近5分をグラフ表示します。ディスク空き容量は60秒ごとに更新します。起動時にMole 1.53系のdry-runを実行し、その後は直近のスキャン完了から60分後に再実行します。左側にGhosttyの埋め込み端末を開けます。未取得値は `—`、グラフの未取得区間は空白で表示します。

## ビルドと起動

Swift 6対応のXcodeを選択した環境で実行します。

```sh
sh scripts/build-app.sh
open build/Puipui.app
```

Finderから `build/Puipui.app` を開くこともできます。チーム `QYP65434UW` のApple Development証明書で署名します。証明書と秘密鍵がキーチェーンに必要です。配布用の公証はしていません。

ログイン時に起動する場合は、アプリを固定した配置先に置いてから、そのアプリ自身で登録します。開発用worktreeのアプリは登録しないでください。

```sh
ditto build/Puipui.app /Applications/Puipui.app
/Applications/Puipui.app/Contents/MacOS/Puipui --register-login-item
```

登録にはmacOSのServiceManagement APIを使い、`loginItemEnabled=true` で有効化を確認します。解除はシステム設定の「ログイン項目と機能拡張」で行えます。

フォルダアクセス許可を更新後も引き継ぐため、同じBundle IDと開発用署名を継続して使います。証明書が見つからない場合はビルドを失敗させ、アドホック署名には切り替えません。従来のアドホック署名から移行した直後は、アクセス許可を再度求められることがあります。

## 操作

- メニューバーの `PUI` をクリックすると、直下にパネルを表示します。Dockには表示しません。
- 上端にカーソルを置くとハンドルが現れます。下へドラッグし、マウスを離すと上にウィンドウボタン領域が伸びます。「視差効果を減らす」が有効な場合はアニメーションしません。
- ウィンドウボタン用の32ptは独立時だけ追加します。通常表示では内容に合わせた高さになります。
- 独立ウィンドウを閉じた後、`PUI` をクリックするとパネルとして再表示します。
- 三点メニューの `Scan` で `mo clean --dry-run` を開始します。クリーンアップ対象は削除しませんが、Moleの候補一覧と操作ログは更新します。スキャン中は再操作できません。手動スキャンも次回予定の起算点を更新します。
- 整理可能容量には前回成功時刻を表示します。更新に失敗したときも前回の成功値と時刻を残し、`Update failed` を併記します。結果はアプリ終了まで保持します。
- 情報アイコンを押すと、最終成功・次回予定・Moleの状態・検出したパスを表示します。矢印のないポップオーバーで、外側クリックかEscで閉じます。Moleが使えない理由もここで確認できます。
- Moleの実行ファイルはログインシェルのPATHから検出します。シェル関数やエイリアスは対象外です。Moleの自動インストール・更新は行いません。環境を直した後は `Scan` で再確認できます。
- 三点メニューの `Quit Puipui` で終了します。
- `Terminal` で左側にGhosttyターミナルを開きます。同じボタンで隠してもセッションは残り、`CLOSE` でシェルを終了します。アプリ終了時もシェルを終了・回収します。
- ターミナルはホームディレクトリで、macOSアカウントに設定されたログインシェルを `-l -i` 付きで起動します。zshなら `.zprofile`・`.zshrc` など通常の設定を読み込みます。整理コマンドは自分で入力します。コマンドの終了は監視していません。空き容量は60秒ごとに更新され、整理可能容量の再集計には `Scan` を使います。
- ターミナルは本体の左端から0.28秒で引き出され、0.20秒で収納されます。文字サイズは変えず、表示領域だけを広げます。「視差効果を減らす」設定では0.10秒のフェードだけになります。

CPU・Memoryのグラフは0〜100%の固定軸です。CPUはUser（niceを含む）とSystemを積み上げて表示します。Memoryの面グラフは使用率、PressureはOSのメモリ圧力通知です。Networkは受信を上、送信を下に描き、両方向に共通の上限を表示中の最大値に合わせて調整します。上下限と中央の補助線、5分前と現在の時間表示を付けています。

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
