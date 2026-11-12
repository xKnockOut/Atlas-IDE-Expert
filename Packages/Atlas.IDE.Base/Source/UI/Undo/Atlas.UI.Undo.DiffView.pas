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
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasUndoDiffView = class(TAtlasDialog)
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
  Atlas.UI.Undo.Strings;

{ TAtlasUndoDiffView }

const
  cViewWidth = 760;

constructor TAtlasUndoDiffView.CreateView(AOwner: TComponent; const ATitle: string; const ALines: TArray<string>);
var
  mBottom: TPanel;
  mLine: string;
begin
  inherited CreateDialog(AOwner, ATitle, cViewWidth);
  BorderIcons := [biSystemMenu, biMaximize];
  Position := poScreenCenter;
  ClientHeight := ScaleValue(480);
  KeyPreview := True;
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.BevelOuter := bvNone;
  mBottom.Height := ScaleValue(40);
  FClose := TButton.Create(Self);
  FClose.Parent := mBottom;
  FClose.Caption := TAtlasUndoStrings.Text(TAtlasUndoTextId.UndoClose);
  FClose.ModalResult := mrCancel;
  FClose.Cancel := True;
  FClose.Default := True;
  FClose.Anchors := [akTop, akRight];
  FClose.Top := ScaleValue(8);
  FClose.Left := mBottom.Width - FClose.Width - ScaleValue(8);
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
    for mLine in ALines do
    begin
      FLines.Lines.Add(mLine);
    end;
  finally
    FLines.Lines.EndUpdate;
  end;
end;

class procedure TAtlasUndoDiffView.Execute(const ATitle: string; const ALines: TArray<string>);
var
  mView: TAtlasUndoDiffView;
begin
  mView := TAtlasUndoDiffView.CreateView(nil, ATitle, ALines);
  try
    mView.ShowModal;
  finally
    mView.Free;
  end;
end;

end.
