unit Atlas.IDE.Commands.MenuModules;

// Einträge der Module (#1455) im Hauptmenü „Atlas“ und unter Ansicht › Atlas.
// Ausgelagert aus Atlas.IDE.Commands.MainMenu. Jedes Modul nennt sie über
// IAtlasMenuSource (Befehl oder eigener Eintrag, Untermenü nach Section,
// Trennlinien aus „-“); Update baut sie hinter der unsichtbaren Marke bei jedem
// Öffnen des Menüs neu auf, UpdateView beim Öffnen von Ansicht › Atlas. So kommen
// und gehen sie mit ihrem Modul (Regel 2); beim Klick wird der Befehl neu gesucht
// (Regel 3). Ein Untermenü ohne sichtbaren Eintrag fehlt.

interface

uses
  System.Classes,
  Vcl.Menus,
  Atlas.Core.Modules.Contract;

type
  /// <summary>Einträge der Module im Atlas-Menü und unter Ansicht › Atlas.</summary>
  TAtlasMenuModuleItems = class
  private
    FRoot: TMenuItem;
    /// <summary>Ab hier stehen die Einträge der Module; unsichtbare Marke.</summary>
    FAnchor: TMenuItem;
    /// <summary>Einträge und Untermenüs direkt im Atlas-Menü; Update baut sie bei jedem Öffnen neu.</summary>
    FItems: TArray<TMenuItem>;
    /// <summary>Befehls-Id je Eintrag (Index = Tag).</summary>
    FIds: TArray<string>;
    /// <summary>Ansicht › Atlas; nil, wenn die IDE kein Menü „Ansicht“ hat.</summary>
    FViewAtlas: TMenuItem;
    /// <summary>Einträge der Module unter Ansicht › Atlas und ihre Befehls-Ids (Index = Tag).</summary>
    FViewItems: TArray<TMenuItem>;
    FViewIds: TArray<string>;
    procedure ItemClick(Sender: TObject);
    procedure ViewItemClick(Sender: TObject);
    /// <summary>Neuer Eintrag für AEntry (Trennlinie, Befehl oder Eintrag ohne Befehl); nil, wenn es den Befehl
    /// nicht mehr gibt.</summary>
    function NewItem(const AEntry: TAtlasMenuEntry): TMenuItem;
    /// <summary>Untermenü ASection; legt es an Position APosition an, wenn es noch fehlt.</summary>
    function SectionOf(const ASection: string; var AGroups: TArray<TMenuItem>; var APosition: Integer): TMenuItem;
    /// <summary>Alte Einträge freigeben; Untermenüs geben ihre Einträge mit frei.</summary>
    procedure Clear;
    /// <summary>Trennlinien und Sichtbarkeit eines Untermenüs der Module.</summary>
    class procedure TidySection(AGroup: TMenuItem); static;
  public
    /// <summary>ARoot: das Atlas-Menü; AAnchor: Marke, hinter der die Einträge stehen.</summary>
    constructor Create(ARoot, AAnchor: TMenuItem);
    /// <summary>Einträge der Module nach der Marke neu aufbauen.</summary>
    procedure Update;
    /// <summary>Einträge der Module unter Ansicht › Atlas neu aufbauen.</summary>
    procedure UpdateView;
    /// <summary>Hat ein laufendes Modul einen sichtbaren Eintrag unter Ansicht › Atlas?</summary>
    class function HasViewItems: Boolean; static;
    property ViewAtlas: TMenuItem read FViewAtlas write FViewAtlas;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Commands.ShortcutTips;

/// <summary>Einträge der Module für APlace.</summary>
function EntriesOf(APlace: TAtlasMenuPlace): TArray<TAtlasMenuEntry>;
begin
  Result := TAtlasModuleContributions.MenuEntries(AtlasModuleRegistry, APlace);
end;

constructor TAtlasMenuModuleItems.Create(ARoot, AAnchor: TMenuItem);
begin
  inherited Create;
  FRoot := ARoot;
  FAnchor := AAnchor;
end;

procedure TAtlasMenuModuleItems.Clear;
var
  mItem: TMenuItem;
begin
  for mItem in FItems do
  begin
    if mItem.Parent = FRoot then
    begin
      mItem.Free;
    end;
  end;
  FItems := nil;
  FIds := nil;
end;

function TAtlasMenuModuleItems.NewItem(const AEntry: TAtlasMenuEntry): TMenuItem;
var
  mCommand: TAtlasModuleCommand;
begin
  Result := nil;
  if AEntry.CommandId = '-' then
  begin
    // Trennlinie; TidySection blendet sie am Rand und doppelt aus.
    Result := TMenuItem.Create(FRoot);
    Result.Caption := '-';
  end
  else if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, AEntry.CommandId, mCommand) then
  begin
    Result := TMenuItem.Create(FRoot);
    Result.Caption := mCommand.Caption;
    Result.Tag := Length(FIds);
    Result.OnClick := ItemClick;
    Result.Visible := TAtlasModuleContributions.IsVisible(mCommand);
    FIds := FIds + [mCommand.Id];
  end
  else if AEntry.Caption <> '' then
  begin
    // Eintrag ohne Befehl (etwa je Projektaufgabe, #900); ohne Run ausgegraut.
    Result := TMenuItem.Create(FRoot);
    Result.Caption := AEntry.Caption;
    Result.Tag := Length(FIds);
    Result.OnClick := ItemClick;
    Result.Enabled := Assigned(AEntry.Run);
    FIds := FIds + [AEntry.CommandId];
  end;
end;

function TAtlasMenuModuleItems.SectionOf(const ASection: string; var AGroups: TArray<TMenuItem>;
  var APosition: Integer): TMenuItem;
var
  mGroup: TMenuItem;
begin
  Result := nil;
  for mGroup in AGroups do
  begin
    if mGroup.Caption = ASection then
    begin
      Result := mGroup;
    end;
  end;
  if Result <> nil then
  begin
    Exit;
  end;
  Result := TMenuItem.Create(FRoot);
  Result.Caption := ASection;
  FRoot.Insert(APosition, Result);
  Inc(APosition);
  AGroups := AGroups + [Result];
  FItems := FItems + [Result];
end;

procedure TAtlasMenuModuleItems.Update;
var
  mEntry: TAtlasMenuEntry;
  mItem, mGroup: TMenuItem;
  mGroups: TArray<TMenuItem>;
  mPosition: Integer;
begin
  if (FRoot = nil) or (FAnchor = nil) then
  begin
    Exit;
  end;
  Clear;
  mGroups := nil;
  mPosition := FAnchor.MenuIndex + 1;
  for mEntry in EntriesOf(TAtlasMenuPlace.AtlasMenu) do
  begin
    mItem := NewItem(mEntry);
    if mItem = nil then
    begin
      Continue;
    end;
    if mEntry.Section = '' then
    begin
      FRoot.Insert(mPosition, mItem);
      Inc(mPosition);
      FItems := FItems + [mItem];
    end
    else
    begin
      SectionOf(mEntry.Section, mGroups, mPosition).Add(mItem);
    end;
  end;
  for mGroup in mGroups do
  begin
    TidySection(mGroup);
  end;
end;

class procedure TAtlasMenuModuleItems.TidySection(AGroup: TMenuItem);
var
  mIndex: Integer;
  mItem: TMenuItem;
  mSeenItem: Boolean;
  mLine: TMenuItem;
begin
  // Trennlinien nur zwischen sichtbaren Einträgen; das Untermenü nur mit mindestens einem.
  mSeenItem := False;
  mLine := nil;
  for mIndex := 0 to AGroup.Count - 1 do
  begin
    mItem := AGroup.Items[mIndex];
    if mItem.IsLine then
    begin
      mItem.Visible := False;
      if mSeenItem then
      begin
        mLine := mItem;
      end;
    end
    else if mItem.Visible then
    begin
      if mLine <> nil then
      begin
        mLine.Visible := True;
      end;
      mLine := nil;
      mSeenItem := True;
    end;
  end;
  AGroup.Visible := mSeenItem;
end;

procedure TAtlasMenuModuleItems.UpdateView;
var
  mItem: TMenuItem;
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
begin
  if FViewAtlas = nil then
  begin
    Exit;
  end;
  for mItem in FViewItems do
  begin
    mItem.Free;
  end;
  FViewItems := nil;
  FViewIds := nil;
  for mEntry in EntriesOf(TAtlasMenuPlace.ViewMenu) do
  begin
    if not TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) then
    begin
      Continue;
    end;
    mItem := TMenuItem.Create(FViewAtlas);
    // Unter Ansicht › Atlas darf der Eintrag einen eigenen Text haben („Atlas: Hotspots“ statt „Hotspots …“).
    mItem.Caption := mEntry.Caption;
    if mItem.Caption = '' then
    begin
      mItem.Caption := mCommand.Caption;
    end;
    mItem.Tag := Length(FViewIds);
    mItem.OnClick := ViewItemClick;
    mItem.Visible := TAtlasModuleContributions.IsVisible(mCommand);
    FViewAtlas.Add(mItem);
    FViewItems := FViewItems + [mItem];
    FViewIds := FViewIds + [mCommand.Id];
  end;
end;

class function TAtlasMenuModuleItems.HasViewItems: Boolean;
var
  mEntry: TAtlasMenuEntry;
  mCommand: TAtlasModuleCommand;
begin
  for mEntry in EntriesOf(TAtlasMenuPlace.ViewMenu) do
  begin
    if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mEntry.CommandId, mCommand) and
      TAtlasModuleContributions.IsVisible(mCommand) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasMenuModuleItems.ViewItemClick(Sender: TObject);
var
  mIndex: Integer;
  mCommand: TAtlasModuleCommand;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex < 0) or (mIndex > High(FViewIds)) then
  begin
    Exit;
  end;
  // Beim Klick neu suchen (Regel 3).
  if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, FViewIds[mIndex], mCommand) and
    Assigned(mCommand.Run) then
  begin
    TAtlasIdeShortcutTips.Invoked(mCommand.Id);
    TAtlasGuard.Run(TAtlasFeature.Menu, mCommand.Run);
  end;
end;

procedure TAtlasMenuModuleItems.ItemClick(Sender: TObject);
var
  mIndex: Integer;
  mId: string;
  mCommand: TAtlasModuleCommand;
  mEntry: TAtlasMenuEntry;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex < 0) or (mIndex > High(FIds)) then
  begin
    Exit;
  end;
  mId := FIds[mIndex];
  // Beim Klick neu suchen (Regel 3): Befehl, sonst Eintrag ohne Befehl.
  if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, mId, mCommand) then
  begin
    if Assigned(mCommand.Run) then
    begin
      TAtlasIdeShortcutTips.Invoked(mId);
      TAtlasGuard.Run(TAtlasFeature.Menu, mCommand.Run);
    end;
  end
  else if TAtlasModuleContributions.FindMenuEntry(AtlasModuleRegistry, TAtlasMenuPlace.AtlasMenu, mId, mEntry) and
    Assigned(mEntry.Run) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Menu, mEntry.Run);
  end;
end;

end.
