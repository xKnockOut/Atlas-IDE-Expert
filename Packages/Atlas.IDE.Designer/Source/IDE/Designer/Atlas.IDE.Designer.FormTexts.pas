unit Atlas.IDE.Designer.FormTexts;

// Befehl „Texte des Formulars …“ (#728) im Menü „Anordnen“ in der IDE: liest
// alle Texte des aktiven Formulars (TAtlasFormTextProps), prüft sie
// (TAtlasFormTexts mit designer.textTable.checks und .synonyms) und zeigt sie
// im Dialog. Ein Klick wählt die Komponente im Designer, jede Änderung setzt
// den Text sofort und ist ein Schritt für „Text rückgängig“. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.IDE.Designer.Tool;

type
  TAtlasIdeFormTexts = class(TAtlasIdeDesignerTool)
  private type
    TChange = record
      Component: string;
      Path: string;
      OldText: string;
    end;
  private
    FUndoFile: string;
    FUndo: TArray<TChange>;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    procedure Execute;
    function CanUndo: Boolean;
    /// <summary>Letzte Änderung zurücknehmen.</summary>
    procedure Undo;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Designer.FormTexts,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.TextsDialog,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FormTextProps,
  Atlas.IDE.Foundation.Settings;

function Recheck(const AEntries: TArray<TAtlasTextEntry>): TArray<TAtlasTextEntry>;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasFormTexts.Check(AEntries, TAtlasFormTexts.ParseChecks(mSettings.DesignerTextTableChecks),
    TAtlasFormTexts.ParseSynonyms(mSettings.DesignerTextTableSynonyms));
end;

// Ohne const: wird als TProc<string> übergeben, Delphi verlangt dieselbe Signatur (E2010).
procedure SelectByName(AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  if TAtlasDesignerAccess.Current(mEditor, mRoot) and (TAtlasDesignerAccess.DesignerOf(mEditor) <> nil) then
  begin
    mComponent := mRoot;
    if not SameText(mRoot.Name, AName) then
    begin
      mComponent := mRoot.FindComponent(AName);
    end;
    if mComponent <> nil then
    begin
      TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
    end;
  end;
end;

function ComponentOf(ARoot: TComponent; const AName: string): TComponent;
begin
  Result := ARoot;
  if not SameText(ARoot.Name, AName) then
  begin
    Result := ARoot.FindComponent(AName);
  end;
end;

{ TAtlasIdeFormTexts }

constructor TAtlasIdeFormTexts.Create(const AOnMessage: TProc<string>);
begin
  inherited Create(AOnMessage);
end;

procedure TAtlasIdeFormTexts.Execute;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mEntries: TArray<TAtlasTextEntry>;
begin
  if not TAtlasIdeSettings.Current.DesignerTextTable or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mEntries := Recheck(TAtlasFormTextProps.Collect(mRoot,
    TAtlasIdeSettings.Current.DesignerTextTableExcludeProperties));
  if Length(mEntries) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerTextsNone));
    Exit;
  end;
  if not SameText(FUndoFile, mEditor.FileName) then
  begin
    FUndoFile := mEditor.FileName;
    FUndo := nil;
  end;
  TAtlasTextsDialog.Execute(mRoot.Name, mEntries, SelectByName,
    function(AIndex: Integer; const AText: string): TArray<TAtlasTextEntry>
    var
      mChange: TChange;
      mComponent: TComponent;
    begin
      mComponent := ComponentOf(mRoot, mEntries[AIndex].Component);
      mChange.Component := mEntries[AIndex].Component;
      mChange.Path := mEntries[AIndex].Path;
      if (mComponent <> nil) and TAtlasFormTextProps.Read(mComponent, mChange.Path, mChange.OldText) and
        TAtlasFormTextProps.Write(mComponent, mChange.Path, AText) then
      begin
        FUndo := FUndo + [mChange];
        TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
        mEntries[AIndex].Text := AText;
      end;
      Result := Recheck(mEntries);
      mEntries := Result;
    end);
end;

function TAtlasIdeFormTexts.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (Length(FUndo) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FUndoFile);
end;

procedure TAtlasIdeFormTexts.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mChange: TChange;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mChange := FUndo[High(FUndo)];
  SetLength(FUndo, Length(FUndo) - 1);
  mComponent := ComponentOf(mRoot, mChange.Component);
  if (mComponent <> nil) and TAtlasFormTextProps.Write(mComponent, mChange.Path, mChange.OldText) then
  begin
    if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
    begin
      TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
    end;
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerTextsUndone, [mChange.Component + '.' + mChange.Path]));
  end;
end;

end.
