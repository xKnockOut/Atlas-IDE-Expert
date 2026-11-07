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

  /// <summary>Texte und Datei des Dialogs: Titel, Hinweis, Vorschau, vorgeschlagener Name, Filter, Endung.</summary>
  TAtlasExportDialogTexts = record
    Title: string;
    Hint: string;
    Preview: string;
    DefaultName: string;
    Filter: string;
    DefaultExt: string;
    class function Create(const ATitle, AHint, APreview, ADefaultName, AFilter,
      ADefaultExt: string): TAtlasExportDialogTexts; static;
    /// <summary>Export des Diagnoselogs: Titel, Dateiname mit Datum und ZIP-Filter.</summary>
    class function Diagnostic(const AHint, APreview: string): TAtlasExportDialogTexts; static;
  end;

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
    constructor CreateDialog(AOwner: TComponent; const ATexts: TAtlasExportDialogTexts); overload;
    /// <summary>True mit AFileName, wenn der Nutzer einen Speicherort gewählt hat.</summary>
    class function Execute(const AHint, APreview: string; out AFileName: string;
      const APrepare: TAtlasExportDialogPrepare): Boolean; overload; static;
    /// <summary>Wie oben mit APrepare = nil.</summary>
    class function Execute(const AHint, APreview: string; out AFileName: string): Boolean; overload; static;
    class function Execute(const ATexts: TAtlasExportDialogTexts; out AFileName: string;
      const APrepare: TAtlasExportDialogPrepare): Boolean; overload; static;
    /// <summary>Wie oben mit APrepare = nil.</summary>
    class function Execute(const ATexts: TAtlasExportDialogTexts; out AFileName: string): Boolean; overload; static;
    property FileName: string read FFileName;
    property HintLabel: TLabel read FHint;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  cGap = 8;

class function TAtlasExportDialogTexts.Create(const ATitle, AHint, APreview, ADefaultName, AFilter,
  ADefaultExt: string): TAtlasExportDialogTexts;
begin
  Result.Title := ATitle;
  Result.Hint := AHint;
  Result.Preview := APreview;
  Result.DefaultName := ADefaultName;
  Result.Filter := AFilter;
  Result.DefaultExt := ADefaultExt;
end;

class function TAtlasExportDialogTexts.Diagnostic(const AHint, APreview: string): TAtlasExportDialogTexts;
begin
  Result := Create(TAtlasStrings.Text(TAtlasTextId.DiagExportTitle), AHint, APreview,
    'atlas-diagnose-' + FormatDateTime('yyyymmdd', Now) + '.zip', TAtlasStrings.Text(TAtlasTextId.DiagExportFilter),
    'zip');
end;

constructor TAtlasDiagnosticExportDialog.CreateDialog(AOwner: TComponent; const AHint, APreview: string);
begin
  CreateDialog(AOwner, TAtlasExportDialogTexts.Diagnostic(AHint, APreview));
end;

constructor TAtlasDiagnosticExportDialog.CreateDialog(AOwner: TComponent; const ATexts: TAtlasExportDialogTexts);
var
  mBottom: TPanel;
  mButton: TButton;
  mHint: TLabel;
  mMemo: TMemo;
begin
  inherited CreateNew(AOwner);
  FDefaultName := ATexts.DefaultName;
  FFilter := ATexts.Filter;
  FDefaultExt := ATexts.DefaultExt;
  Caption := ATexts.Title;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := 900;
  Height := 600;

  mHint := TLabel.Create(Self);
  mHint.Parent := Self;
  mHint.Align := alTop;
  mHint.AlignWithMargins := True;
  mHint.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mHint.WordWrap := True;
  // Breite vor dem Text: Sonst misst die Beschriftung mit ihrer Standardbreite, bricht nach jedem Wort um und
  // bleibt so hoch, dass die Vorschau kaum Platz hat.
  mHint.Width := Width - 2 * cGap;
  mHint.Caption := ATexts.Hint;
  FHint := mHint;
  OnResize := FitHint;

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := 44;
  mBottom.BevelOuter := bvNone;
  mButton := TButton.Create(Self);
  mButton.Parent := mBottom;
  mButton.SetBounds(mBottom.Width - 2 * (100 + cGap), 8, 100, 28);
  mButton.Anchors := [akTop, akRight];
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.DiagExportSave);
  mButton.Default := True;
  mButton.OnClick := SaveClick;
  mButton := TButton.Create(Self);
  mButton.Parent := mBottom;
  mButton.SetBounds(mBottom.Width - (100 + cGap), 8, 100, 28);
  mButton.Anchors := [akTop, akRight];
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;

  mMemo := TMemo.Create(Self);
  mMemo.Parent := Self;
  mMemo.Align := alClient;
  mMemo.AlignWithMargins := True;
  mMemo.Margins.SetBounds(cGap, 0, cGap, 0);
  mMemo.ReadOnly := True;
  mMemo.ScrollBars := ssBoth;
  mMemo.WordWrap := False;
  mMemo.Font.Name := 'Consolas';
  mMemo.Font.Size := 9;
  mMemo.Lines.Text := ATexts.Preview;
end;

procedure TAtlasDiagnosticExportDialog.FitHint(Sender: TObject);
begin
  // AutoSize misst nur beim Setzen neu; nach Breitenänderung (DPI, Größe) die Höhe zum Umbruch passend machen.
  FHint.AutoSize := False;
  FHint.AutoSize := True;
end;

procedure TAtlasDiagnosticExportDialog.SaveClick(Sender: TObject);
var
  mDialog: TSaveDialog;
begin
  mDialog := TSaveDialog.Create(Self);
  try
    mDialog.Filter := FFilter;
    mDialog.DefaultExt := FDefaultExt;
    mDialog.FileName := FDefaultName;
    mDialog.Options := mDialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if not mDialog.Execute then
    begin
      Exit;
    end;
    FFileName := mDialog.FileName;
    ModalResult := mrOk;
  finally
    mDialog.Free;
  end;
end;

class function TAtlasDiagnosticExportDialog.Execute(const AHint, APreview: string; out AFileName: string): Boolean;
begin
  Result := Execute(TAtlasExportDialogTexts.Diagnostic(AHint, APreview), AFileName, nil);
end;

class function TAtlasDiagnosticExportDialog.Execute(const AHint, APreview: string; out AFileName: string;
  const APrepare: TAtlasExportDialogPrepare): Boolean;
begin
  Result := Execute(TAtlasExportDialogTexts.Diagnostic(AHint, APreview), AFileName, APrepare);
end;

class function TAtlasDiagnosticExportDialog.Execute(const ATexts: TAtlasExportDialogTexts;
  out AFileName: string): Boolean;
begin
  Result := Execute(ATexts, AFileName, nil);
end;

class function TAtlasDiagnosticExportDialog.Execute(const ATexts: TAtlasExportDialogTexts; out AFileName: string;
  const APrepare: TAtlasExportDialogPrepare): Boolean;
var
  mDialog: TAtlasDiagnosticExportDialog;
begin
  mDialog := TAtlasDiagnosticExportDialog.CreateDialog(nil, ATexts);
  try
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    Result := mDialog.ShowModal = mrOk;
    AFileName := mDialog.FileName;
  finally
    mDialog.Free;
  end;
end;

end.
