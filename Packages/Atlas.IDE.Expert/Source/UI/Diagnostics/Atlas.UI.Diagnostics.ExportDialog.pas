unit Atlas.UI.Diagnostics.ExportDialog;

// Vorschau vor dem Export des Diagnoselogs (#647): zeigt genau die Zeilen, die
// in die ZIP-Datei kommen, und fragt nach dem Speicherort. Geschrieben wird
// nicht hier, sondern vom Aufrufer (TAtlasDiagnosticExport.WriteZip).
// Dieselbe Vorschau dient dem Fehlerbericht (#108) mit eigenem Titel,
// Dateinamen und Filter.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Dialogs,
  Vcl.Graphics;

type
  /// <summary>Vorbereitung vor dem Zeigen, etwa das Thema der IDE (die UI-Schicht kennt es nicht).</summary>
  TAtlasExportDialogPrepare = reference to procedure(AControl: TWinControl);

  TAtlasDiagnosticExportDialog = class(TForm)
  private
    FHint: TLabel;
    FFileName: string;
    FDefaultName: string;
    FFilter: string;
    FDefaultExt: string;
    procedure SaveClick(Sender: TObject);
    procedure FitHint(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const AHint, APreview: string); overload;
    /// <summary>Mit eigenem Titel, vorgeschlagenem Dateinamen, Filter und Endung.</summary>
    constructor CreateDialog(AOwner: TComponent; const ATitle, AHint, APreview, ADefaultName, AFilter,
      ADefaultExt: string); overload;
    /// <summary>True mit AFileName, wenn der Nutzer einen Speicherort gewählt hat.</summary>
    class function Execute(const AHint, APreview: string; out AFileName: string;
      const APrepare: TAtlasExportDialogPrepare = nil): Boolean; overload; static;
    class function Execute(const ATitle, AHint, APreview, ADefaultName, AFilter, ADefaultExt: string;
      out AFileName: string; const APrepare: TAtlasExportDialogPrepare = nil): Boolean; overload; static;
    property FileName: string read FFileName;
    property HintLabel: TLabel read FHint;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  Gap = 8;

constructor TAtlasDiagnosticExportDialog.CreateDialog(AOwner: TComponent; const AHint, APreview: string);
begin
  CreateDialog(AOwner, TAtlasStrings.Text(TAtlasTextId.DiagExportTitle), AHint, APreview,
    'atlas-diagnose-' + FormatDateTime('yyyymmdd', Now) + '.zip', TAtlasStrings.Text(TAtlasTextId.DiagExportFilter),
    'zip');
end;

constructor TAtlasDiagnosticExportDialog.CreateDialog(AOwner: TComponent; const ATitle, AHint, APreview,
  ADefaultName, AFilter, ADefaultExt: string);
var
  Bottom: TPanel;
  Button: TButton;
  mHint: TLabel;
  Memo: TMemo;
begin
  inherited CreateNew(AOwner);
  FDefaultName := ADefaultName;
  FFilter := AFilter;
  FDefaultExt := ADefaultExt;
  Caption := ATitle;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := 900;
  Height := 600;

  mHint := TLabel.Create(Self);
  mHint.Parent := Self;
  mHint.Align := alTop;
  mHint.AlignWithMargins := True;
  mHint.Margins.SetBounds(Gap, Gap, Gap, Gap);
  mHint.WordWrap := True;
  // Breite vor dem Text: Sonst misst die Beschriftung mit ihrer Standardbreite, bricht nach jedem Wort um und
  // bleibt so hoch, dass die Vorschau kaum Platz hat.
  mHint.Width := Width - 2 * Gap;
  mHint.Caption := AHint;
  FHint := mHint;
  OnResize := FitHint;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Bottom.Width - 2 * (100 + Gap), 8, 100, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.DiagExportSave);
  Button.Default := True;
  Button.OnClick := SaveClick;
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Bottom.Width - (100 + Gap), 8, 100, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  Button.Cancel := True;
  Button.ModalResult := mrCancel;

  Memo := TMemo.Create(Self);
  Memo.Parent := Self;
  Memo.Align := alClient;
  Memo.AlignWithMargins := True;
  Memo.Margins.SetBounds(Gap, 0, Gap, 0);
  Memo.ReadOnly := True;
  Memo.ScrollBars := ssBoth;
  Memo.WordWrap := False;
  Memo.Font.Name := 'Consolas';
  Memo.Font.Size := 9;
  Memo.Lines.Text := APreview;
end;

procedure TAtlasDiagnosticExportDialog.FitHint(Sender: TObject);
begin
  // AutoSize misst nur beim Setzen neu; nach Breitenänderung (DPI, Größe) die Höhe zum Umbruch passend machen.
  FHint.AutoSize := False;
  FHint.AutoSize := True;
end;

procedure TAtlasDiagnosticExportDialog.SaveClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := FFilter;
    Dialog.DefaultExt := FDefaultExt;
    Dialog.FileName := FDefaultName;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if not Dialog.Execute then
      Exit;
    FFileName := Dialog.FileName;
    ModalResult := mrOk;
  finally
    Dialog.Free;
  end;
end;

class function TAtlasDiagnosticExportDialog.Execute(const ATitle, AHint, APreview, ADefaultName, AFilter,
  ADefaultExt: string; out AFileName: string; const APrepare: TAtlasExportDialogPrepare): Boolean;
var
  Dialog: TAtlasDiagnosticExportDialog;
begin
  Dialog := TAtlasDiagnosticExportDialog.CreateDialog(nil, ATitle, AHint, APreview, ADefaultName, AFilter,
    ADefaultExt);
  try
    if Assigned(APrepare) then
      APrepare(Dialog);
    Result := Dialog.ShowModal = mrOk;
    AFileName := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

class function TAtlasDiagnosticExportDialog.Execute(const AHint, APreview: string; out AFileName: string;
  const APrepare: TAtlasExportDialogPrepare): Boolean;
var
  Dialog: TAtlasDiagnosticExportDialog;
begin
  Dialog := TAtlasDiagnosticExportDialog.CreateDialog(nil, AHint, APreview);
  try
    if Assigned(APrepare) then
      APrepare(Dialog);
    Result := Dialog.ShowModal = mrOk;
    AFileName := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

end.
