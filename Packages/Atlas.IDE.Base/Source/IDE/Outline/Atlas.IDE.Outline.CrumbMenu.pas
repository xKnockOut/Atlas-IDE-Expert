unit Atlas.IDE.Outline.CrumbMenu;

// Rechtsklick-Menü an den Gliedern der Brotkrumenleiste in der IDE (#1786).
// Welche Einträge ein Glied bekommt und was sie liefern, rechnet
// TAtlasCrumbMenu aus Gliederung und Text; hier bleiben Menü, Zwischenablage,
// Ergebnisfenster, Umbenennen und Designer.
// - Kopieren: Name mit Besitzer, mit Unit davor, Kopf der Routine, Pfad der
//   ganzen Leiste; am Unit-Glied Unit-Name und Dateipfad.
// - Ergebnisfenster, Umbenennen und Formulartext kommen als Haken aus der
//   Komposition (TAtlasCrumbMenuHooks), damit die Gliederung nicht von Editor
//   und Ergebnissen abhängt (keine Feature-Zyklen).
// - „Verwendungen suchen“ fragt am Namen der Deklaration und zeigt das
//   Ergebnis im Ergebnisfenster wie „Verwendungen suchen“ am Cursor.
// - „Umbenennen …“ setzt den Cursor auf den Namen und ruft das Umbenennen
//   der Komposition, damit Rückfrage und Vorschau wie gewohnt laufen.
// - „Komponente im Designer zeigen“ gibt es für Komponentenfelder und
//   Ereignisbehandler, die im Formulartext (.dfm/.fmx neben der Unit, Stand
//   des Designers) vorkommen; der Designer geht auf und wählt die Komponente.
// Das Menü ist ein TPopupMenu; der Eintrag läuft erst nach dem Schließen
// (WM_COMMAND), deshalb lebt der Zustand bis zum nächsten Menü. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs;

type
  /// <summary>Verwendungen am Namen (Datei, Zeile, Spalte 0-basiert, Name) im Ergebnisfenster zeigen.</summary>
  TAtlasCrumbReferences = reference to procedure(const AFileName: string; ALine, ACharacter: Integer;
    const AName: string);

  /// <summary>Was das Menü von außerhalb der Gliederung braucht; die Komposition setzt es.</summary>
  TAtlasCrumbMenuHooks = record
    /// <summary>Symbol am Cursor umbenennen (mit Rückfrage und Vorschau).</summary>
    Rename: TProc;
    References: TAtlasCrumbReferences;
    /// <summary>Aktueller Text einer Datei (offener Puffer, Stand des Designers, sonst Platte); '' ohne.</summary>
    CurrentText: TFunc<string, string>;
  end;

  TAtlasIdeCrumbMenu = class
  private class var
    FState: TObject;
  public
    /// <summary>Menü für Glied AIndex aus ACrumbs an der Bildschirmstelle APoint.</summary>
    class procedure Show(const APoint: TPoint; const AFileName: string; const ANodes: TAtlasOutlineNodes;
      const ALines: TArray<string>; const ACrumbs: TAtlasCrumbs; AIndex: Integer;
      const AHooks: TAtlasCrumbMenuHooks); static;
    /// <summary>Gibt das zuletzt gezeigte Menü frei.</summary>
    class procedure Release; static;
  end;

implementation

uses
  Vcl.Menus,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Outline.CrumbMenu,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Navigation;

const
  cTexts: array[TAtlasCrumbAction] of TAtlasTextId = (TAtlasTextId.CrumbCopyName, TAtlasTextId.CrumbCopyWithUnit,
    TAtlasTextId.CrumbCopySignature, TAtlasTextId.CrumbCopyPath, TAtlasTextId.CrumbShowComponent,
    TAtlasTextId.CrumbFindReferences, TAtlasTextId.CrumbRename, TAtlasTextId.CrumbCopyUnitName,
    TAtlasTextId.CrumbCopyFilePath);
  /// <summary>Reihenfolge im Menü; vor FindReferences und vor CopyUnitName steht ein Trennstrich.</summary>
  cOrder: array[0..8] of TAtlasCrumbAction = (TAtlasCrumbAction.CopyName, TAtlasCrumbAction.CopyWithUnit,
    TAtlasCrumbAction.CopySignature, TAtlasCrumbAction.CopyPath, TAtlasCrumbAction.ShowComponent,
    TAtlasCrumbAction.FindReferences, TAtlasCrumbAction.Rename, TAtlasCrumbAction.CopyUnitName,
    TAtlasCrumbAction.CopyFilePath);

type
  TCrumbMenuState = class
  private
    FMenu: TPopupMenu;
    FFileName: string;
    FNodes: TAtlasOutlineNodes;
    FLines: TArray<string>;
    FCrumbs: TAtlasCrumbs;
    FIndex: Integer;
    FComponent: string;
    FHooks: TAtlasCrumbMenuHooks;
    procedure Clicked(Sender: TObject);
    procedure Run(AAction: TAtlasCrumbAction);
    function Crumb: TAtlasCrumb;
    function UnitName: string;
    /// <summary>Knoten der Deklaration zum Glied (Name für Suche und Umbenennen); -1 ohne.</summary>
    function Declaration: Integer;
    procedure ShowComponent;
  public
    constructor Create(const AFileName: string; const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const ACrumbs: TAtlasCrumbs; AIndex: Integer; const AHooks: TAtlasCrumbMenuHooks);
    destructor Destroy; override;
    procedure Popup(const APoint: TPoint);
  end;

/// <summary>Formulartext neben der Unit (.dfm, sonst .fmx) über ACurrentText; '' ohne.</summary>
function FormTextOf(const AFileName: string; const ACurrentText: TFunc<string, string>): string;
begin
  Result := '';
  if not Assigned(ACurrentText) then
  begin
    Exit;
  end;
  if FileExists(ChangeFileExt(AFileName, '.dfm')) then
  begin
    Result := ACurrentText(ChangeFileExt(AFileName, '.dfm'));
  end
  else if FileExists(ChangeFileExt(AFileName, '.fmx')) then
  begin
    Result := ACurrentText(ChangeFileExt(AFileName, '.fmx'));
  end;
end;

/// <summary>Formular-Editor des Moduls AFileName; nil, wenn das Modul nicht offen ist oder kein Formular hat.
/// </summary>
function FormEditorOf(const AFileName: string): IOTAFormEditor;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.FindModule(AFileName);
  if mModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mModule.ModuleFileCount - 1 do
  begin
    if Supports(mModule.ModuleFileEditors[mIndex], IOTAFormEditor, Result) then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

{ TCrumbMenuState }

constructor TCrumbMenuState.Create(const AFileName: string; const ANodes: TAtlasOutlineNodes;
  const ALines: TArray<string>; const ACrumbs: TAtlasCrumbs; AIndex: Integer; const AHooks: TAtlasCrumbMenuHooks);
begin
  inherited Create;
  FFileName := AFileName;
  FNodes := ANodes;
  FLines := ALines;
  FCrumbs := ACrumbs;
  FIndex := AIndex;
  FHooks := AHooks;
  FMenu := TPopupMenu.Create(nil);
end;

destructor TCrumbMenuState.Destroy;
begin
  FMenu.Free;
  inherited Destroy;
end;

function TCrumbMenuState.Crumb: TAtlasCrumb;
begin
  Result := FCrumbs[FIndex];
end;

function TCrumbMenuState.UnitName: string;
begin
  Result := ChangeFileExt(ExtractFileName(FFileName), '');
end;

function TCrumbMenuState.Declaration: Integer;
begin
  Result := -1;
  if (Crumb.Node >= 0) and (Crumb.Node <= High(FNodes)) then
  begin
    Result := TAtlasBreadcrumbs.Target(FNodes, Crumb.Node, False);
  end;
end;

procedure TCrumbMenuState.Popup(const APoint: TPoint);
var
  mActions: TAtlasCrumbActions;
  mAction: TAtlasCrumbAction;
  mItem: TMenuItem;
begin
  FComponent := '';
  if TAtlasCrumbMenu.MemberOf(FNodes, Crumb.Node) <> '' then
  begin
    FComponent := TAtlasCrumbMenu.ComponentOf(FormTextOf(FFileName, FHooks.CurrentText),
      TAtlasCrumbMenu.MemberOf(FNodes, Crumb.Node));
  end;
  mActions := TAtlasCrumbMenu.ActionsOf(FNodes, Crumb, FComponent <> '');
  for mAction in cOrder do
  begin
    if not (mAction in mActions) then
    begin
      Continue;
    end;
    if (mAction in [TAtlasCrumbAction.FindReferences, TAtlasCrumbAction.CopyUnitName]) and (FMenu.Items.Count > 0) then
    begin
      FMenu.Items.Add(NewLine);
    end;
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasStrings.Text(cTexts[mAction]);
    mItem.Tag := Ord(mAction);
    mItem.OnClick := Clicked;
    FMenu.Items.Add(mItem);
  end;
  TAtlasGuard.Log(Format('Breadcrumbs: context menu on crumb %d, %d items', [FIndex, FMenu.Items.Count]));
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TCrumbMenuState.Clicked(Sender: TObject);
var
  mAction: TAtlasCrumbAction;
begin
  mAction := TAtlasCrumbAction(TMenuItem(Sender).Tag);
  TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
    procedure
    begin
      Run(mAction);
    end);
end;

procedure TCrumbMenuState.Run(AAction: TAtlasCrumbAction);
var
  mTarget: Integer;
begin
  TAtlasGuard.Log(Format('Breadcrumbs: context menu item %d', [Ord(AAction)]));
  mTarget := Declaration;
  case AAction of
    TAtlasCrumbAction.CopyName:
      Clipboard.AsText := TAtlasCrumbMenu.NameOf(FNodes, Crumb.Node);
    TAtlasCrumbAction.CopyWithUnit:
      Clipboard.AsText := UnitName + '.' + TAtlasCrumbMenu.NameOf(FNodes, Crumb.Node);
    TAtlasCrumbAction.CopySignature:
      Clipboard.AsText := TAtlasCrumbMenu.SignatureOf(FNodes, FLines, Crumb.Node);
    TAtlasCrumbAction.CopyPath:
      Clipboard.AsText := TAtlasCrumbMenu.PathOf(FCrumbs);
    TAtlasCrumbAction.CopyUnitName:
      Clipboard.AsText := UnitName;
    TAtlasCrumbAction.CopyFilePath:
      Clipboard.AsText := FFileName;
    TAtlasCrumbAction.ShowComponent:
      ShowComponent;
    TAtlasCrumbAction.FindReferences:
      if (mTarget >= 0) and Assigned(FHooks.References) then
      begin
        FHooks.References(FFileName, FNodes[mTarget].NameLine, FNodes[mTarget].NameCharacter,
          TAtlasBreadcrumbs.ShortName(FNodes[mTarget].Name));
      end;
    TAtlasCrumbAction.Rename:
      if (mTarget >= 0) and Assigned(FHooks.Rename) then
      begin
        TAtlasIdeNavigation.GoToLocation(FFileName, FNodes[mTarget].NameLine, FNodes[mTarget].NameCharacter);
        FHooks.Rename();
      end;
  end;
end;

procedure TCrumbMenuState.ShowComponent;
var
  mEditor: IOTAFormEditor;
  mComponent: IOTAComponent;
begin
  mEditor := FormEditorOf(FFileName);
  if mEditor = nil then
  begin
    TAtlasGuard.Log('Breadcrumbs: no form editor for the unit');
    Exit;
  end;
  mEditor.Show;
  mComponent := mEditor.FindComponent(FComponent);
  if mComponent = nil then
  begin
    // Ereignis des Formulars selbst oder Komponente noch nicht im Designer: das Formular wählen.
    mComponent := mEditor.GetRootComponent;
  end;
  if mComponent <> nil then
  begin
    mComponent.Select(False);
  end;
end;

{ TAtlasIdeCrumbMenu }

class procedure TAtlasIdeCrumbMenu.Show(const APoint: TPoint; const AFileName: string;
  const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; const ACrumbs: TAtlasCrumbs; AIndex: Integer;
  const AHooks: TAtlasCrumbMenuHooks);
begin
  Release;
  if (AIndex < 0) or (AIndex > High(ACrumbs)) then
  begin
    Exit;
  end;
  FState := TCrumbMenuState.Create(AFileName, ANodes, ALines, ACrumbs, AIndex, AHooks);
  TCrumbMenuState(FState).Popup(APoint);
end;

class procedure TAtlasIdeCrumbMenu.Release;
begin
  FreeAndNil(FState);
end;

end.
