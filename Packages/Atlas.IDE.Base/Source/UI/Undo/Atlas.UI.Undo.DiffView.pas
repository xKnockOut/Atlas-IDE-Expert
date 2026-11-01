unit Atlas.UI.Undo.DiffView;

// Unterschied einer Atlas-Änderung (#721) aus der Liste „Atlas-Änderungen“:
// ein kleines Fenster mit den Zeilen vorher („- “) und nachher („+ “) in
// fester Schrift, Esc oder „Schließen“ beendet es. Der Text kommt vom
// Aufrufer (TAtlasUndoMessages.DiffLines).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  TAtlasUndoDiffView = class(TForm)
  private
    FLines: TMemo;
    FClose: TButton;
  public
    constructor CreateView(AOwner: TComponent; const ATitle: string; const ALines: TArray<string>);
    /// <summary>Modal zeigen und freigeben.</summary>
    class procedure Execute(const ATitle: string; const ALines: TArray<string>); static;
    property Lines: TMemo read FLines;
    property CloseButton: TButton read FClose;
  end;

implementation

uses
  Atlas.UI.Strings;

{ TAtlasUndoDiffView }

constructor TAtlasUndoDiffView.CreateView(AOwner: TComponent; const ATitle: string; const ALines: TArray<string>);
var
  Bottom: TPanel;
  Line: string;
begin
  inherited CreateNew(AOwner);
  Caption := ATitle;
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poScreenCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(760);
  ClientHeight := ScaleValue(480);
  KeyPreview := True;
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.BevelOuter := bvNone;
  Bottom.Height := ScaleValue(40);
  FClose := TButton.Create(Self);
  FClose.Parent := Bottom;
  FClose.Caption := TAtlasStrings.Text(TAtlasTextId.UndoClose);
  FClose.ModalResult := mrCancel;
  FClose.Cancel := True;
  FClose.Default := True;
  FClose.Anchors := [akTop, akRight];
  FClose.Top := ScaleValue(8);
  FClose.Left := Bottom.Width - FClose.Width - ScaleValue(8);
  FLines := TMemo.Create(Self);
  FLines.Parent := Self;
  FLines.Align := alClient;
  FLines.AlignWithMargins := True;
  FLines.ReadOnly := True;
  FLines.WordWrap := False;
  FLines.ScrollBars := ssBoth;
  FLines.Font.Name := 'Consolas';
  FLines.Lines.BeginUpdate;
  try
    for Line in ALines do
      FLines.Lines.Add(Line);
  finally
    FLines.Lines.EndUpdate;
  end;
end;

class procedure TAtlasUndoDiffView.Execute(const ATitle: string; const ALines: TArray<string>);
var
  View: TAtlasUndoDiffView;
begin
  View := TAtlasUndoDiffView.CreateView(nil, ATitle, ALines);
  try
    View.ShowModal;
  finally
    View.Free;
  end;
end;

end.
