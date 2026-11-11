unit Atlas.IDE.Outline.CrumbLists;

// Sprungmenüs der Brotkrumenleiste (#590) als Atlas-Popup unter dem Glied:
// - Geschwister und Kinder eines Glieds in Quelltextreihenfolge, das aktuelle
//   gewählt, Filter mit Wortgrenzen-Suche; Enter springt zur Implementierung
//   (ohne Rumpf zur Deklaration), Umschalt+Enter zur Deklaration.
// - Überladungen (#1784) mit Parametern und Zeile.
// - „Erfüllt“ (#1785): Interface-Methoden mit Unit und Zeile; Enter springt
//   zur Deklaration im Interface, auch in anderen Units.
// - Sprungziele eines Glieds ohne Knoten (Sichtbarkeitsabschnitte #1759,
//   Regionen #1764); beim Sichtbarkeitsglied dahinter „Neue Zeile am Ende
//   von …“ und „Abschnitt anlegen: …“ (#1768) über TAtlasIdeSectionEdit.
// Dazu die Aufbereitung der Glieder: Namen für Regionen ohne Text und
// Interface-Marken. Jedes Menü arbeitet auf Kopien des Stands, weil es länger
// lebt als dieser. Nur im Hauptthread.

interface

uses
  System.Types,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.Interfaces,
  Atlas.UI.Outline.Breadcrumbs;

type
  /// <summary>Stand der Datei, aus dem die Menüs springen: Datei, Gliederung, Zeilen und Caret (0-basiert).
  /// </summary>
  TAtlasCrumbSource = record
    FileName: string;
    Nodes: TAtlasOutlineNodes;
    Lines: TArray<string>;
    Line: Integer;
    Character: Integer;
  end;

  /// <summary>Welches Menü am Glied aufgeht.</summary>
{$SCOPEDENUMS ON}
  TAtlasCrumbList = (Siblings, Children, Overloads, Interfaces);
{$SCOPEDENUMS OFF}

  TAtlasIdeCrumbLists = class
  public
    /// <summary>Menü AList am Glied AIndex der Leiste ABar an APoint (Bildschirm) öffnen. Geschwister eines
    /// Glieds ohne Knoten sind seine Sprungziele.</summary>
    class procedure Open(AList: TAtlasCrumbList; const ASource: TAtlasCrumbSource; ABar: TAtlasBreadcrumbBar;
      AIndex: Integer; const APoint: TPoint); static;
    /// <summary>Glieder zum Zeigen: Regionen ohne Text bekommen einen Namen (#1764), Methodenglieder die
    /// erfüllten Interface-Methoden aus AInterfaces (#1785, leer = ohne Marke).</summary>
    class function Prepared(const ACrumbs: TAtlasCrumbs; const AInterfaces: TAtlasInterfaceMethods;
      const ANodes: TAtlasOutlineNodes): TAtlasCrumbs; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Outline.VisibilitySections,
  Atlas.Core.Outline.SectionEdit,
  Atlas.Core.Outline.Overloads,
  Atlas.UI.Outline.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Outline.SectionEdit,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings;

const
  cMenuWidth = 380;
  /// <summary>Kennungen der Menüeinträge „Neue Zeile am Ende von …“ und „Abschnitt anlegen“ (#1768).</summary>
  cAppendId = 'append:';
  cCreateId = 'create:';
  /// <summary>Höchstlänge von Name und Parametern im Menü (#1784); länger mit „…“.</summary>
  cOverloadCaptionMax = 56;

type
  /// <summary>Knoten eines Menüs (Geschwister, Kinder oder Überladungen) mit dem vorgewählten Knoten; Overloads
  /// zeigt statt des Pfads nur die Zeile.</summary>
  TCrumbListItems = record
    Items: TArray<Integer>;
    Current: Integer;
    Overloads: Boolean;
  end;

/// <summary>Knoten AItems mit Vorwahl ACurrent als ein Wert.</summary>
function ListItems(const AItems: TArray<Integer>; ACurrent: Integer; AOverloads: Boolean): TCrumbListItems;
begin
  Result.Items := AItems;
  Result.Current := ACurrent;
  Result.Overloads := AOverloads;
end;

/// <summary>Text eines Sprungziels; Regionen ohne Namen als „Region (Z. n)“ (#1764).</summary>
function PlaceText(const APlace: TAtlasCrumbPlace): string;
begin
  Result := APlace.Text;
  if Result = '' then
  begin
    Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsRegionUnnamed), [APlace.Line + 1]);
  end;
end;

/// <summary>Palette mit den Einstellungen aller Sprungmenüs: Prompt, vorsortiert, Filter ohne Verzögerung.
/// </summary>
function NewPalette(const ACommands: TArray<TAtlasCommand>; const APrompt: string): TAtlasPaletteWindow;
begin
  Result := TAtlasPaletteWindow.CreatePalette(Application, ACommands, nil, TAtlasIdeStyle.Colors);
  Result.Prompt := APrompt;
  Result.Presorted := True;
  Result.QueryDelay := 0;
end;

function CommandsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const AIndices: TArray<Integer>; ACurrent: Integer; AOverloads: Boolean): TArray<TAtlasCommand>;
var
  mNode: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mNode in AIndices do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mNode);
    mCommand.Caption := TAtlasBreadcrumbs.ShortName(ANodes[mNode].Name);
    mCommand.Path := ANodes[mNode].Detail;
    // Überladungen (#1784) mit Parametern, gekürzt; der Hinweis zeigt die volle Liste.
    if AOverloads or (TAtlasIdeSettings.Current.BreadcrumbsOverloads and
      (Length(TAtlasOverloads.Find(ANodes, mNode)) > 0)) then
    begin
      mCommand.Caption := TAtlasOverloads.Caption(ANodes, ALines, mNode, cOverloadCaptionMax);
      mCommand.Description := TAtlasOverloads.Caption(ANodes, ALines, mNode, MaxInt);
    end;
    if AOverloads then
    begin
      mCommand.Path := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsPlaceLineOnly),
        [ANodes[mNode].NameLine + 1]);
    end;
    if mNode = ACurrent then
    begin
      mCommand.ShortCut := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsCurrent);
    end;
    Result := Result + [mCommand];
  end;
end;

/// <summary>Menü der Knoten AList; vorgewählt ist AList.Current.</summary>
procedure OpenList(const ASource: TAtlasCrumbSource; ABar: TAtlasBreadcrumbBar; const APrompt: string;
  const AList: TCrumbListItems; const APoint: TPoint);
var
  mItems: TArray<Integer>;
  mCurrent: Integer;
  mOverloads: Boolean;
  mNodes: TAtlasOutlineNodes;
  mLines: TArray<string>;
  mFileName: string;
  mWindow: TAtlasPaletteWindow;
begin
  if (Length(AList.Items) = 0) or (ASource.FileName = '') then
  begin
    TAtlasGuard.Log(Format('Brotkrumen: kein Menü (Einträge %d, Datei %s)', [Length(AList.Items),
      BoolToStr(ASource.FileName <> '', True)]));
    Exit;
  end;
  // Kopien: Das Menü lebt länger als der aktuelle Stand.
  mItems := AList.Items;
  mCurrent := AList.Current;
  mOverloads := AList.Overloads;
  mNodes := ASource.Nodes;
  mLines := ASource.Lines;
  mFileName := ASource.FileName;
  mWindow := NewPalette(CommandsOf(mNodes, mLines, mItems, mCurrent, mOverloads), APrompt);
  mWindow.RowHints := True;
  if mCurrent >= 0 then
  begin
    mWindow.InitialId := IntToStr(mCurrent);
  end;
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := CommandsOf(mNodes, mLines, TAtlasBreadcrumbs.Filter(mNodes, mItems, APattern), mCurrent,
        mOverloads);
    end;
  mWindow.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      Node, Target: Integer;
    begin
      Node := StrToIntDef(ACommand.Id, -1);
      // Enter zur Implementierung, Umschalt+Enter zur Deklaration.
      Target := -1;
      if (Node >= 0) and (Node <= High(mNodes)) then
      begin
        Target := TAtlasBreadcrumbs.Target(mNodes, Node, not AShifted);
      end;
      if Target >= 0 then
      begin
        TAtlasIdeNavigation.GoToLocation(mFileName, mNodes[Target].NameLine, mNodes[Target].NameCharacter);
      end;
    end;
  mWindow.ShowAt(APoint, MulDiv(cMenuWidth, ABar.CurrentPPI, 96));
end;

/// <summary>Einträge des Menüs „Erfüllt“ (#1785), die zum Muster APattern passen: Interface-Methode, darunter
/// Datei und Zeile.</summary>
function InterfaceCommands(const ATargets: TAtlasInterfaceTargets; const APattern: string): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mIndex := 0 to High(ATargets) do
  begin
    if not TAtlasBreadcrumbs.MatchesAtWordStart(APattern, ATargets[mIndex].Name) then
    begin
      Continue;
    end;
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    mCommand.Caption := ATargets[mIndex].Name;
    mCommand.Path := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesPath),
      [ExtractFileName(ATargets[mIndex].FileName), ATargets[mIndex].Line + 1]);
    Result := Result + [mCommand];
  end;
end;

/// <summary>Menü „Erfüllt“ an der Interface-Marke des Glieds (#1785): Interface-Methoden mit Unit und Zeile; Enter
/// springt zur Deklaration im Interface.</summary>
procedure OpenInterfaces(ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  mTargets: TAtlasInterfaceTargets;
  mWindow: TAtlasPaletteWindow;
begin
  // Kopie: Das Menü lebt länger als der aktuelle Stand.
  mTargets := ABar.Crumbs[AIndex].Interfaces;
  if Length(mTargets) = 0 then
  begin
    Exit;
  end;
  mWindow := NewPalette(InterfaceCommands(mTargets, ''),
    TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsInterfacesPrompt));
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := InterfaceCommands(mTargets, APattern);
    end;
  mWindow.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    var
      mChosen: Integer;
    begin
      mChosen := StrToIntDef(ACommand.Id, -1);
      if (mChosen >= 0) and (mChosen <= High(mTargets)) and (mTargets[mChosen].FileName <> '') then
      begin
        TAtlasIdeNavigation.GoToLocation(mTargets[mChosen].FileName, mTargets[mChosen].Line,
          mTargets[mChosen].Character);
      end;
    end;
  mWindow.ShowAt(APoint, MulDiv(cMenuWidth, ABar.CurrentPPI, 96));
end;

/// <summary>Menü der Kinder unter dem „›“ hinter dem Glied AIndex.</summary>
procedure OpenChildren(const ASource: TAtlasCrumbSource; ABar: TAtlasBreadcrumbBar; AIndex: Integer;
  const APoint: TPoint);
var
  mCrumb: TAtlasCrumb;
  mCurrent, mNext: Integer;
begin
  mCrumb := ABar.Crumbs[AIndex];
  // Vorgewählt ist das Kind, in dem der Caret steht: das nächste Glied mit Knoten (ein Abschnittsglied
  // dazwischen hat keinen).
  mCurrent := -1;
  mNext := AIndex + 1;
  while (mCurrent < 0) and (mNext <= High(ABar.Crumbs)) do
  begin
    mCurrent := ABar.Crumbs[mNext].Node;
    Inc(mNext);
  end;
  OpenList(ASource, ABar, mCrumb.Text + ' ›', ListItems(mCrumb.Children, mCurrent, False), APoint);
end;

/// <summary>Gedimmte Zeile eines Sprungziels: bei Sichtbarkeitsabschnitten mit Mitgliederzahl (#1768,
/// ACounts), bei Deklarationsblöcken (#1766) mit dem Teil der Unit, sonst nur die Zeile.</summary>
function PlacePath(const APlace: TAtlasCrumbPlace; ACounts: Boolean): string;
begin
  if ACounts and (APlace.Mark <> '') then
  begin
    if APlace.Count = 1 then
    begin
      Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionCountOne), [APlace.Line + 1]);
    end
    else
    begin
      Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionCount), [APlace.Count,
        APlace.Line + 1]);
    end;
  end
  else if APlace.Group <> '' then
  begin
    Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsPlaceLine), [APlace.Group,
      APlace.Line + 1]);
  end
  else
  begin
    Result := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsPlaceLineOnly), [APlace.Line + 1]);
  end;
end;

function PlaceCommands(const APlaces: TArray<TAtlasCrumbPlace>; const APattern: string;
  ACurrent: Integer; ACounts: Boolean): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
  mText: string;
begin
  Result := nil;
  for mIndex := 0 to High(APlaces) do
  begin
    mText := PlaceText(APlaces[mIndex]);
    if not TAtlasBreadcrumbs.MatchesAtWordStart(APattern, mText) then
    begin
      Continue;
    end;
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    // Verschachtelte Regionen (#1764) eingerückt.
    mCommand.Caption := StringOfChar(' ', 4 * APlaces[mIndex].Depth) + mText;
    // Marke der Gliederung vor dem Abschnitt (#1768).
    if ACounts and (APlaces[mIndex].Mark <> '') then
    begin
      mCommand.Caption := APlaces[mIndex].Mark + ' ' + mCommand.Caption;
    end;
    mCommand.Path := PlacePath(APlaces[mIndex], ACounts);
    if mIndex = ACurrent then
    begin
      mCommand.ShortCut := TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsCurrent);
    end;
    Result := Result + [mCommand];
  end;
end;

/// <summary>Einträge „Neue Zeile am Ende von …“ je Abschnitt und „Abschnitt anlegen: …“ je fehlendem Abschnitt
/// (#1768), soweit an und zum Muster passend.</summary>
function SectionCommands(const APlaces: TArray<TAtlasCrumbPlace>; const AMissing: TArray<string>;
  const APattern: string): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
  mKeyword: string;
begin
  Result := nil;
  if TAtlasIdeSettings.Current.BreadcrumbsSectionAppend then
  begin
    for mIndex := 0 to High(APlaces) do
    begin
      mCommand := Default(TAtlasCommand);
      mCommand.Id := cAppendId + IntToStr(mIndex);
      mCommand.Caption := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionAppend),
        [APlaces[mIndex].Text]);
      if TAtlasBreadcrumbs.MatchesAtWordStart(APattern, mCommand.Caption) then
      begin
        Result := Result + [mCommand];
      end;
    end;
  end;
  if TAtlasIdeSettings.Current.BreadcrumbsSectionCreate then
  begin
    for mKeyword in AMissing do
    begin
      mCommand := Default(TAtlasCommand);
      mCommand.Id := cCreateId + mKeyword;
      mCommand.Caption := Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsSectionCreate), [mKeyword]);
      if TAtlasBreadcrumbs.MatchesAtWordStart(APattern, mCommand.Caption) then
      begin
        Result := Result + [mCommand];
      end;
    end;
  end;
end;

/// <summary>Sprungziele und, beim Sichtbarkeitsglied (AEditable), die Einträge zum Ändern (#1768).</summary>
function MenuCommands(const APlaces: TArray<TAtlasCrumbPlace>; const AMissing: TArray<string>;
  const APattern: string; ACurrent: Integer; ACounts, AEditable: Boolean): TArray<TAtlasCommand>;
begin
  Result := PlaceCommands(APlaces, APattern, ACurrent, ACounts);
  if AEditable then
  begin
    Result := Result + SectionCommands(APlaces, AMissing, APattern);
  end;
end;

/// <summary>Eintrag AId des Menüs der Sprungziele ausführen: Zeile anhängen, Abschnitt anlegen oder springen.
/// </summary>
procedure RunPlace(const ASource: TAtlasCrumbSource; const APlaces: TArray<TAtlasCrumbPlace>; const AId: string);
var
  mChosen: Integer;
begin
  if AId.StartsWith(cAppendId) then
  begin
    TAtlasIdeSectionEdit.Append(ASource.FileName, ASource.Nodes, ASource.Lines, ASource.Line, ASource.Character,
      StrToIntDef(AId.Substring(Length(cAppendId)), -2));
  end
  else if AId.StartsWith(cCreateId) then
  begin
    TAtlasIdeSectionEdit.Add(ASource.FileName, ASource.Nodes, ASource.Lines, ASource.Line, ASource.Character,
      AId.Substring(Length(cCreateId)));
  end
  else
  begin
    mChosen := StrToIntDef(AId, -1);
    if (mChosen >= 0) and (mChosen <= High(APlaces)) then
    begin
      TAtlasIdeNavigation.GoToLocation(ASource.FileName, APlaces[mChosen].Line, APlaces[mChosen].Character);
    end;
  end;
end;

/// <summary>Menü der Sprungziele eines Glieds ohne Knoten (Sichtbarkeitsabschnitte des Typs, #1759); beim
/// Sichtbarkeitsglied dahinter „Neue Zeile am Ende von …“ und „Abschnitt anlegen: …“ (#1768).</summary>
procedure OpenPlaces(const ASource: TAtlasCrumbSource; ABar: TAtlasBreadcrumbBar; const ACrumb: TAtlasCrumb;
  const APoint: TPoint);
var
  mSource: TAtlasCrumbSource;
  mPlaces: TArray<TAtlasCrumbPlace>;
  mMissing: TArray<string>;
  mCurrent: Integer;
  mCounts, mEditable: Boolean;
  mWindow: TAtlasPaletteWindow;
begin
  if ASource.FileName = '' then
  begin
    Exit;
  end;
  // Kopien: Das Menü lebt länger als der aktuelle Stand.
  mSource := ASource;
  mPlaces := ACrumb.Places;
  mCurrent := ACrumb.Current;
  mCounts := TAtlasIdeSettings.Current.BreadcrumbsSectionCounts;
  // Nur das Sichtbarkeitsglied bekommt die Einträge zum Ändern.
  mEditable := ACrumb.SectionType >= 0;
  mMissing := nil;
  if mEditable then
  begin
    mMissing := TAtlasSectionEditor.Missing(mSource.Nodes, TAtlasVisibilitySectionFinder.At(mSource.Nodes,
      mSource.Lines, mSource.Line, mSource.Character));
  end;
  mWindow := NewPalette(MenuCommands(mPlaces, mMissing, '', mCurrent, mCounts, mEditable), ACrumb.Text);
  if mCurrent >= 0 then
  begin
    mWindow.InitialId := IntToStr(mCurrent);
  end;
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      Result := MenuCommands(mPlaces, mMissing, APattern, mCurrent, mCounts, mEditable);
    end;
  mWindow.OnExecuteShift :=
    procedure(ACommand: TAtlasCommand; AShifted: Boolean)
    begin
      RunPlace(mSource, mPlaces, ACommand.Id);
    end;
  mWindow.ShowAt(APoint, MulDiv(cMenuWidth, ABar.CurrentPPI, 96));
end;

{ TAtlasIdeCrumbLists }

class procedure TAtlasIdeCrumbLists.Open(AList: TAtlasCrumbList; const ASource: TAtlasCrumbSource;
  ABar: TAtlasBreadcrumbBar; AIndex: Integer; const APoint: TPoint);
var
  mCrumb: TAtlasCrumb;
begin
  mCrumb := ABar.Crumbs[AIndex];
  case AList of
    TAtlasCrumbList.Siblings:
      if Length(mCrumb.Places) > 0 then
      begin
        OpenPlaces(ASource, ABar, mCrumb, APoint);
      end
      else
      begin
        OpenList(ASource, ABar, mCrumb.Text, ListItems(mCrumb.Siblings, mCrumb.Node, False), APoint);
      end;
    TAtlasCrumbList.Children:
      OpenChildren(ASource, ABar, AIndex, APoint);
    TAtlasCrumbList.Overloads:
      OpenList(ASource, ABar, Format(TAtlasOutlineStrings.Text(TAtlasOutlineTextId.BreadcrumbsOverloadsPrompt),
        [mCrumb.Text]), ListItems(mCrumb.Overloads, mCrumb.Node, True), APoint);
    TAtlasCrumbList.Interfaces:
      OpenInterfaces(ABar, AIndex, APoint);
  end;
end;

class function TAtlasIdeCrumbLists.Prepared(const ACrumbs: TAtlasCrumbs; const AInterfaces: TAtlasInterfaceMethods;
  const ANodes: TAtlasOutlineNodes): TAtlasCrumbs;
var
  mIndex: Integer;
begin
  Result := ACrumbs;
  for mIndex := 0 to High(Result) do
  begin
    if (Result[mIndex].Text = '') and (Result[mIndex].Current >= 0) and
      (Result[mIndex].Current <= High(Result[mIndex].Places)) then
    begin
      Result[mIndex].Text := PlaceText(Result[mIndex].Places[Result[mIndex].Current]);
    end;
    if Length(AInterfaces) > 0 then
    begin
      Result[mIndex].Interfaces := TAtlasOutlineInterfaces.TargetsOf(AInterfaces, ANodes, Result[mIndex].Node);
    end;
  end;
end;

end.
