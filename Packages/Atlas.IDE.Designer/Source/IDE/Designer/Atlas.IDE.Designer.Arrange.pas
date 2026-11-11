unit Atlas.IDE.Designer.Arrange;

// Knopf „Anordnen“ der Designer-Leiste (#730 ff.) in der IDE: Menü mit den
// Befehlen, die Größe und Lage der markierten Steuerelemente ändern. Jeder
// Befehl hat eine eigene Einstellung; ist keiner an, fehlt der Knopf.
// - Breite nach Text (#730, designer.fitToText, TAtlasIdeFitText).
// - Knopfleiste anordnen (#732, designer.buttonBar, TAtlasIdeButtonBar).
// - In Reihe duplizieren … und dessen Rückgängig (#736, designer.duplicateRow,
//   TAtlasIdeDuplicateRow).
// - Platz einfügen …, Platz entfernen … und dessen Rückgängig (#740,
//   designer.insertSpace, TAtlasIdeInsertSpace).
// Gesperrt sind Einträge, für die die Auswahl nicht passt. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Designer.DuplicateRow,
  Atlas.IDE.Designer.InsertSpace;

type
  TAtlasIdeDesignerArrange = class
  private
    FMenu: TPopupMenu;
    FOnMessage: TProc<string>;
    FDuplicate: TAtlasIdeDuplicateRow;
    FSpace: TAtlasIdeInsertSpace;
    procedure AddItem(const ACaption: string; ATag: Integer; AEnabled: Boolean);
    procedure ItemClick(Sender: TObject);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Ist mindestens ein Befehl eingeschaltet?</summary>
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Menü für die Auswahl im aktiven Designer an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
    procedure ApplyTheme;
  end;

implementation

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Designer.ButtonBar,
  Atlas.IDE.Foundation.Settings;

const
  cFitToText = 1;
  cButtonBar = 2;
  cDuplicate = 3;
  cDuplicateUndo = 4;
  cSpaceInsert = 5;
  cSpaceRemove = 6;
  cSpaceUndo = 7;

{ TAtlasIdeDesignerArrange }

constructor TAtlasIdeDesignerArrange.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FMenu := TPopupMenu.Create(nil);
  FDuplicate := TAtlasIdeDuplicateRow.Create(AOnMessage);
  FSpace := TAtlasIdeInsertSpace.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerArrange.Destroy;
begin
  FSpace.Free;
  FDuplicate.Free;
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasIdeDesignerArrange.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerFitToText or ASettings.DesignerButtonBar or ASettings.DesignerDuplicateRow or
    ASettings.DesignerInsertSpace;
end;

procedure TAtlasIdeDesignerArrange.AddItem(const ACaption: string; ATag: Integer; AEnabled: Boolean);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := ACaption;
  mItem.Tag := ATag;
  mItem.Enabled := AEnabled;
  mItem.OnClick := ItemClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasIdeDesignerArrange.Popup(const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not Available(mSettings) or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  FMenu.Items.Clear;
  if mSettings.DesignerFitToText then
  begin
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitToText), cFitToText,
      Length(TAtlasIdeFitText.Candidates(mSelected)) > 0);
  end;
  if mSettings.DesignerButtonBar then
  begin
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerButtonBarCmd), cButtonBar,
      Length(TAtlasIdeButtonBar.Candidates(mSelected)) > 0);
  end;
  if mSettings.DesignerDuplicateRow then
  begin
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateCmd), cDuplicate,
      Length(TAtlasIdeDuplicateRow.Candidates(mSelected)) > 0);
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateUndoCmd), cDuplicateUndo,
      FDuplicate.CanUndo);
  end;
  if mSettings.DesignerInsertSpace then
  begin
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceInsertCmd), cSpaceInsert,
      Length(TAtlasIdeInsertSpace.Candidates(mSelected)) > 0);
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceRemoveCmd), cSpaceRemove,
      Length(TAtlasIdeInsertSpace.Candidates(mSelected)) > 0);
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceUndoCmd), cSpaceUndo, FSpace.CanUndo);
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeDesignerArrange.ItemClick(Sender: TObject);
var
  mTag: Integer;
  mOnMessage: TProc<string>;
  mDuplicate: TAtlasIdeDuplicateRow;
  mSpace: TAtlasIdeInsertSpace;
begin
  mTag := TMenuItem(Sender).Tag;
  mOnMessage := FOnMessage;
  mDuplicate := FDuplicate;
  mSpace := FSpace;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      case mTag of
        cFitToText:
          TAtlasIdeFitText.Execute(mOnMessage);
        cButtonBar:
          TAtlasIdeButtonBar.Execute(mOnMessage);
        cDuplicate:
          mDuplicate.Execute;
        cDuplicateUndo:
          mDuplicate.Undo;
        cSpaceInsert:
          mSpace.Execute(False);
        cSpaceRemove:
          mSpace.Execute(True);
        cSpaceUndo:
          mSpace.Undo;
      end;
    end);
end;

procedure TAtlasIdeDesignerArrange.ApplyTheme;
begin
  FDuplicate.ApplyTheme;
end;

end.
