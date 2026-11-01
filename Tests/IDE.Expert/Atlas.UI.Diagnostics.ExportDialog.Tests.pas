unit Atlas.UI.Diagnostics.ExportDialog.Tests;

// Vorschau vor dem Export (#647, #108, #1356): Der Hinweis oben bleibt so
// niedrig wie sein Umbruch, damit die Vorschau der Dateien Platz hat.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDiagnosticExportDialogTests = class
  public
    /// <summary>Erste Benutzung (VCL, Schriften) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    /// <summary>Langer Hinweis: wenige Zeilen hoch, nicht ein Wort je Zeile.</summary>
    [Test]
    procedure HintKeepsItsWrappedHeight;
    /// <summary>Schmaler gezogen: Die Höhe wächst mit dem Umbruch mit.</summary>
    [Test]
    procedure HintFollowsWidth;
    [Test]
    procedure PrepareRunsBeforeShowing;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.UI.Diagnostics.ExportDialog;

const
  LongHint = 'Das Paket enthält die Dateien unten: Fehlerbericht, Status, Protokoll der Sitzung und, mit --trace, ' +
    'den Trace der letzten Minuten. Pfade, Benutzername und Bezeichner sind ersetzt. Zugangsdaten stehen nie darin.';

procedure TAtlasDiagnosticExportDialogTests.WarmUpFirstUse;
begin
  HintKeepsItsWrappedHeight;
  // Erste modale Anzeige legt einmalige VCL-Zustände an.
  PrepareRunsBeforeShowing;
end;

procedure TAtlasDiagnosticExportDialogTests.HintKeepsItsWrappedHeight;
var
  mDialog: TAtlasDiagnosticExportDialog;
  mLine: Integer;
begin
  mDialog := TAtlasDiagnosticExportDialog.CreateDialog(nil, 'Titel', LongHint, 'Vorschau', 'a.zip', '*.zip', 'zip');
  try
    mLine := mDialog.Canvas.TextHeight('Ag');
    Assert.IsTrue(mDialog.HintLabel.Height <= 4 * mLine,
      Format('Hinweis %d px hoch bei %d px je Zeile', [mDialog.HintLabel.Height, mLine]));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDiagnosticExportDialogTests.HintFollowsWidth;
var
  mDialog: TAtlasDiagnosticExportDialog;
  mWide: Integer;
begin
  mDialog := TAtlasDiagnosticExportDialog.CreateDialog(nil, 'Titel', LongHint, 'Vorschau', 'a.zip', '*.zip', 'zip');
  try
    mWide := mDialog.HintLabel.Height;
    mDialog.Width := 400;
    Assert.IsTrue(mDialog.HintLabel.Height > mWide);
    mDialog.Width := 900;
    Assert.AreEqual(mWide, mDialog.HintLabel.Height);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDiagnosticExportDialogTests.PrepareRunsBeforeShowing;
var
  mSeen: TWinControl;
  mFile: string;
begin
  mSeen := nil;
  // Der Haken läuft vor ShowModal. ModalResult setzt ShowModal zurück; darum schließt eine Nachricht, die erst die
  // modale Schleife abholt.
  Assert.IsFalse(TAtlasDiagnosticExportDialog.Execute('Hinweis', 'Vorschau', mFile,
    procedure(AControl: TWinControl)
    begin
      mSeen := AControl;
      PostMessage(AControl.Handle, WM_CLOSE, 0, 0);
    end));
  Assert.IsTrue(mSeen is TAtlasDiagnosticExportDialog);
end;

end.