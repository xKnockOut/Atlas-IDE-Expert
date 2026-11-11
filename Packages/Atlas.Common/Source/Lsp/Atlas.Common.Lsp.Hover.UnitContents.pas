unit Atlas.Common.Lsp.Hover.UnitContents;

// Inhalt einer Unit im Hover über ihren Namen (#1921), etwa über einem
// uses-Eintrag: die Typen aus dem interface-Teil nach Art gruppiert (Klassen,
// Interfaces, Records, Aufzählungen, sonstige Typen), dazu Routinen,
// Konstanten und Variablen; je Gruppe alphabetisch, generische Typen mit
// ihren Typparametern. Deklarationen in inaktiven Zweigen der bedingten
// Kompilierung fehlen.
//
// Collect nimmt alles aus dem Index und merkt sich, was die Datei des Hovers
// davon benutzt (TUsesActions.NamesUsed: nach dem Namen, so großzügig wie die
// Prüfung auf ungenutzte uses-Einträge). Select wählt nach hints.unitContents
// aus: off nichts, types nur die Typen, usedFirst die Typen mit den benutzten
// vorn, all wie usedFirst und dazu Routinen, Konstanten und Variablen.
//
// Ausgabe als Markdown und Klartext für andere Editoren und als Abschnitte
// "unitContents" der strukturierten Doku für den Atlas-Tooltip: je Gruppe ein
// Abschnitt mit Überschrift (heading), Gruppenname (name) und den Namen als
// Verweise mit Fundort, die das Plugin anklickbar macht. Je Gruppe stehen
// höchstens cMaxPerGroup Namen da, dahinter die Zahl der übrigen.

interface

uses
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Gruppe eines Eintrags in Anzeigereihenfolge.</summary>
  THoverUnitGroup = (Classes, Interfaces, Records, Enums, OtherTypes, Routines, Constants, Variables);
  /// <summary>Was der Hover zeigt (hints.unitContents).</summary>
  THoverUnitMode = (Off, Types, UsedFirst, All);
  {$SCOPEDENUMS OFF}

  /// <summary>Deklaration auf Unit-Ebene mit Fundort des Namens (0-basiert).</summary>
  THoverUnitEntry = record
    /// <summary>Name, bei generischen Typen mit Typparametern (TList&lt;T&gt;).</summary>
    Name: string;
    Group: THoverUnitGroup;
    /// <summary>Die Datei des Hovers nennt den Namen.</summary>
    Used: Boolean;
    FileName: string;
    Line: Integer;
    Character: Integer;
    function IsType: Boolean;
  end;

  /// <summary>Ausgewählter Inhalt; Mode Off oder ohne Einträge zeigt der Hover nichts.</summary>
  THoverUnitContents = record
    Mode: THoverUnitMode;
    Entries: TArray<THoverUnitEntry>;
    function IsEmpty: Boolean;
    function ToMarkdown: string;
    function ToPlainText: string;
    /// <summary>Hängt je Gruppe einen Abschnitt "unitContents" an ASections an.</summary>
    procedure AddSections(ASections: TJSONArray);
  end;

  TLspHoverUnitContents = class
  public const
    cMaxPerGroup = 200;
  public
    /// <summary>Alle Deklarationen auf Unit-Ebene aus dem interface von AUnit, sortiert nach Gruppe und Name, mit
    /// Used aus ATokens (Datei des Hovers).</summary>
    class function Collect(const AUnit: TUnitIndex; const ATokens: TArray<TPascalToken>): TArray<THoverUnitEntry>;
      static;
    /// <summary>Auswahl nach AMode; die Reihenfolge von AEntries bleibt.</summary>
    class function Select(const AEntries: TArray<THoverUnitEntry>; AMode: THoverUnitMode): THoverUnitContents;
      static;
    /// <summary>Wert von hints.unitContents; Unbekanntes ergibt UsedFirst.</summary>
    class function ModeOf(const AName: string): THoverUnitMode; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Lsp.IdeUnits,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TUnitContentsText = (UsedHeading, MoreHeading, TypesHeading, OthersHeading, NoTypeUsed, NothingUsed, More,
    Classes, Interfaces, Records, Enums, OtherTypes, Routines, Constants, Variables);

const
  cTexts: array[TUnitContentsText] of TAtlasText = (
    (De: 'IN DIESER DATEI BENUTZT (%d)'; En: 'USED IN THIS FILE (%d)'),
    (De: 'WEITERE TYPEN (%d)'; En: 'MORE TYPES (%d)'),
    (De: 'TYPEN (%d)'; En: 'TYPES (%d)'),
    (De: 'ROUTINEN, KONSTANTEN UND VARIABLEN (%d)'; En: 'ROUTINES, CONSTANTS AND VARIABLES (%d)'),
    (De: 'Kein Typ der Unit wird hier benutzt'; En: 'No type of this unit is used here'),
    (De: 'Nichts aus der Unit wird hier benutzt'; En: 'Nothing from this unit is used here'),
    (De: ' … %d weitere'; En: ' … %d more'),
    (De: 'Klassen'; En: 'Classes'),
    (De: 'Interfaces'; En: 'Interfaces'),
    (De: 'Records'; En: 'Records'),
    (De: 'Aufzählungen'; En: 'Enumerations'),
    (De: 'Sonstige'; En: 'Other'),
    (De: 'Routinen'; En: 'Routines'),
    (De: 'Konstanten'; En: 'Constants'),
    (De: 'Variablen'; En: 'Variables'));

{$SCOPEDENUMS OFF}

const
  cSectionKind = 'unitContents';
  cGroupTexts: array[THoverUnitGroup] of TUnitContentsText = (TUnitContentsText.Classes,
    TUnitContentsText.Interfaces, TUnitContentsText.Records, TUnitContentsText.Enums, TUnitContentsText.OtherTypes,
    TUnitContentsText.Routines, TUnitContentsText.Constants, TUnitContentsText.Variables);

type
  /// <summary>Eine Gruppe unter einer Überschrift; Group ohne Bedeutung, wenn Entries leer ist (dann steht Note
  /// da).</summary>
  TContentsBlock = record
    Heading: string;
    Group: THoverUnitGroup;
    Entries: TArray<THoverUnitEntry>;
    Note: string;
  end;

{ THoverUnitEntry }

function THoverUnitEntry.IsType: Boolean;
begin
  Result := Group < THoverUnitGroup.Routines;
end;

function GroupOf(AKind: TIndexSymbolKind; out AGroup: THoverUnitGroup): Boolean;
begin
  Result := True;
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType: AGroup := THoverUnitGroup.Classes;
    TIndexSymbolKind.InterfaceType: AGroup := THoverUnitGroup.Interfaces;
    TIndexSymbolKind.RecordType: AGroup := THoverUnitGroup.Records;
    TIndexSymbolKind.EnumType: AGroup := THoverUnitGroup.Enums;
    TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias: AGroup := THoverUnitGroup.OtherTypes;
    TIndexSymbolKind.Routine: AGroup := THoverUnitGroup.Routines;
    TIndexSymbolKind.Constant: AGroup := THoverUnitGroup.Constants;
    TIndexSymbolKind.Variable: AGroup := THoverUnitGroup.Variables;
  else
    Result := False;
  end;
end;

function DisplayName(const ASymbol: TIndexSymbol): string;
begin
  Result := ASymbol.Name;
  if ASymbol.TypeParams <> '' then
  begin
    Result := Result + '<' + ASymbol.TypeParams + '>';
  end;
end;

function EntryOf(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol; AGroup: THoverUnitGroup): THoverUnitEntry;
begin
  Result := Default(THoverUnitEntry);
  Result.Name := DisplayName(ASymbol);
  Result.Group := AGroup;
  Result.FileName := ASymbol.FileName;
  if Result.FileName = '' then
  begin
    Result.FileName := AUnit.FileName;
  end;
  Result.Line := ASymbol.SelectionRange.StartPos.Line;
  Result.Character := ASymbol.SelectionRange.StartPos.Character;
end;

function CompareEntries(const A, B: THoverUnitEntry): Integer;
begin
  Result := Ord(A.Group) - Ord(B.Group);
  if Result = 0 then
  begin
    Result := CompareText(A.Name, B.Name);
  end;
end;

{ TLspHoverUnitContents }

class function TLspHoverUnitContents.Collect(const AUnit: TUnitIndex;
  const ATokens: TArray<TPascalToken>): TArray<THoverUnitEntry>;
var
  mSymbol: TIndexSymbol;
  mGroup: THoverUnitGroup;
  mSeen: TDictionary<string, Boolean>;
  mNames: TArray<string>;
  mUsed: TArray<Boolean>;
  mIndex: Integer;
  mEntry: THoverUnitEntry;
begin
  Result := nil;
  mNames := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mSymbol in AUnit.Symbols do
    begin
      // Überladene Routinen und Vorwärtsdeklarationen nur einmal.
      if (mSymbol.Container <> '') or not mSymbol.InInterface or mSymbol.Unavailable or
        not GroupOf(mSymbol.Kind, mGroup) then
      begin
        Continue;
      end;
      mEntry := EntryOf(AUnit, mSymbol, mGroup);
      if mSeen.ContainsKey(LowerCase(mEntry.Name)) then
      begin
        Continue;
      end;
      mSeen.Add(LowerCase(mEntry.Name), True);
      Result := Result + [mEntry];
      mNames := mNames + [mSymbol.Name];
    end;
  finally
    mSeen.Free;
  end;
  mUsed := TUsesActions.NamesUsed(ATokens, mNames);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex].Used := mUsed[mIndex];
  end;
  TArray.Sort<THoverUnitEntry>(Result, TComparer<THoverUnitEntry>.Construct(
    function(const A, B: THoverUnitEntry): Integer
    begin
      Result := CompareEntries(A, B);
    end));
end;

class function TLspHoverUnitContents.Select(const AEntries: TArray<THoverUnitEntry>;
  AMode: THoverUnitMode): THoverUnitContents;
var
  mEntry: THoverUnitEntry;
begin
  Result := Default(THoverUnitContents);
  Result.Mode := AMode;
  if AMode = THoverUnitMode.Off then
  begin
    Exit;
  end;
  for mEntry in AEntries do
  begin
    if (AMode = THoverUnitMode.All) or mEntry.IsType then
    begin
      Result.Entries := Result.Entries + [mEntry];
    end;
  end;
end;

class function TLspHoverUnitContents.ModeOf(const AName: string): THoverUnitMode;
begin
  if SameText(AName, THintSettings.cUnitContentsOff) then
  begin
    Result := THoverUnitMode.Off;
  end
  else if SameText(AName, THintSettings.cUnitContentsTypes) then
  begin
    Result := THoverUnitMode.Types;
  end
  else if SameText(AName, THintSettings.cUnitContentsAll) then
  begin
    Result := THoverUnitMode.All;
  end
  else
  begin
    Result := THoverUnitMode.UsedFirst;
  end;
end;

{ Blöcke }

/// <summary>Einträge von AEntries, deren Used gleich AUsed ist und die (bei AOnlyTypes) Typen sind; ohne
/// AFilter alle.</summary>
function Filtered(const AEntries: TArray<THoverUnitEntry>; AFilter, AUsed, AOnlyTypes: Boolean;
  out AOthers: TArray<THoverUnitEntry>): TArray<THoverUnitEntry>;
var
  mEntry: THoverUnitEntry;
begin
  Result := nil;
  AOthers := nil;
  for mEntry in AEntries do
  begin
    if AFilter and (mEntry.Used <> AUsed) then
    begin
      Continue;
    end;
    if AOnlyTypes and not mEntry.IsType then
    begin
      AOthers := AOthers + [mEntry];
    end
    else
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

/// <summary>Je Gruppe von AEntries (nach Gruppe sortiert) ein Block unter AHeading.</summary>
procedure AddGroups(var ABlocks: TArray<TContentsBlock>; const AHeading: string;
  const AEntries: TArray<THoverUnitEntry>);
var
  mEntry: THoverUnitEntry;
  mBlock: TContentsBlock;
begin
  for mEntry in AEntries do
  begin
    if (Length(ABlocks) = 0) or (ABlocks[High(ABlocks)].Heading <> AHeading) or
      (Length(ABlocks[High(ABlocks)].Entries) = 0) or (ABlocks[High(ABlocks)].Group <> mEntry.Group) then
    begin
      mBlock := Default(TContentsBlock);
      mBlock.Heading := AHeading;
      mBlock.Group := mEntry.Group;
      ABlocks := ABlocks + [mBlock];
    end;
    ABlocks[High(ABlocks)].Entries := ABlocks[High(ABlocks)].Entries + [mEntry];
  end;
end;

function BlocksOf(const AContents: THoverUnitContents): TArray<TContentsBlock>;
var
  mUsed, mMore, mOthers, mNone: TArray<THoverUnitEntry>;
  mNote: TContentsBlock;
begin
  Result := nil;
  if AContents.IsEmpty then
  begin
    Exit;
  end;
  if AContents.Mode = THoverUnitMode.Types then
  begin
    AddGroups(Result, cTexts[TUnitContentsText.TypesHeading].Fmt([Length(AContents.Entries)]), AContents.Entries);
    Exit;
  end;
  mUsed := Filtered(AContents.Entries, True, True, False, mNone);
  mMore := Filtered(AContents.Entries, True, False, True, mOthers);
  if Length(mUsed) = 0 then
  begin
    mNote := Default(TContentsBlock);
    mNote.Heading := cTexts[TUnitContentsText.UsedHeading].Fmt([0]);
    if AContents.Mode = THoverUnitMode.All then
    begin
      mNote.Note := cTexts[TUnitContentsText.NothingUsed].Text;
    end
    else
    begin
      mNote.Note := cTexts[TUnitContentsText.NoTypeUsed].Text;
    end;
    Result := [mNote];
  end;
  AddGroups(Result, cTexts[TUnitContentsText.UsedHeading].Fmt([Length(mUsed)]), mUsed);
  AddGroups(Result, cTexts[TUnitContentsText.MoreHeading].Fmt([Length(mMore)]), mMore);
  AddGroups(Result, cTexts[TUnitContentsText.OthersHeading].Fmt([Length(mOthers)]), mOthers);
end;

function GroupName(const ABlock: TContentsBlock): string;
begin
  Result := '';
  if Length(ABlock.Entries) > 0 then
  begin
    Result := cTexts[cGroupTexts[ABlock.Group]].Text;
  end;
end;

/// <summary>Namen des Blocks, durch Komma getrennt, bei AQuote in Backticks; dahinter die Zahl der übrigen.
/// </summary>
function NameList(const ABlock: TContentsBlock; AQuote: Boolean): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to Length(ABlock.Entries) - 1 do
  begin
    if mIndex = TLspHoverUnitContents.cMaxPerGroup then
    begin
      Exit(Result + cTexts[TUnitContentsText.More].Fmt([Length(ABlock.Entries) - mIndex]));
    end;
    if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    if AQuote then
    begin
      Result := Result + '`' + ABlock.Entries[mIndex].Name + '`';
    end
    else
    begin
      Result := Result + ABlock.Entries[mIndex].Name;
    end;
  end;
end;

{ THoverUnitContents }

function THoverUnitContents.IsEmpty: Boolean;
begin
  Result := (Mode = THoverUnitMode.Off) or (Length(Entries) = 0);
end;

function THoverUnitContents.ToMarkdown: string;
var
  mBlock: TContentsBlock;
  mHeading: string;
begin
  Result := '';
  mHeading := '';
  for mBlock in BlocksOf(Self) do
  begin
    if mBlock.Heading <> mHeading then
    begin
      if Result <> '' then
      begin
        Result := Result + #10#10;
      end;
      Result := Result + '**' + mBlock.Heading + '**' + #10;
      mHeading := mBlock.Heading;
    end;
    if mBlock.Note <> '' then
    begin
      Result := Result + #10 + '- ' + mBlock.Note;
    end
    else
    begin
      Result := Result + #10 + '- ' + GroupName(mBlock) + ': ' + NameList(mBlock, True);
    end;
  end;
end;

function THoverUnitContents.ToPlainText: string;
var
  mBlock: TContentsBlock;
  mHeading: string;
begin
  Result := '';
  mHeading := '';
  for mBlock in BlocksOf(Self) do
  begin
    if mBlock.Heading <> mHeading then
    begin
      if Result <> '' then
      begin
        Result := Result + #10#10;
      end;
      Result := Result + mBlock.Heading;
      mHeading := mBlock.Heading;
    end;
    if mBlock.Note <> '' then
    begin
      Result := Result + #10 + mBlock.Note;
    end
    else
    begin
      Result := Result + #10 + GroupName(mBlock) + ': ' + NameList(mBlock, False);
    end;
  end;
end;

function TextRun(const AText: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', 'text');
  Result.AddPair('text', AText);
end;

/// <summary>Verweis mit Fundort; Ersatz-Units der IDE (atlas-ide:…) ohne Datei, also ohne Sprungziel.</summary>
function RefRun(const AEntry: THoverUnitEntry): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', 'ref');
  Result.AddPair('text', AEntry.Name);
  Result.AddPair('target', AEntry.Name);
  Result.AddPair('name', AEntry.Name);
  if not TIdeUnits.IsIdePath(AEntry.FileName) then
  begin
    Result.AddPair('file', AEntry.FileName);
    Result.AddPair('line', TJSONNumber.Create(AEntry.Line));
    Result.AddPair('character', TJSONNumber.Create(AEntry.Character));
  end;
end;

function BlockRuns(const ABlock: TContentsBlock): TJSONArray;
var
  mIndex: Integer;
begin
  Result := TJSONArray.Create;
  if ABlock.Note <> '' then
  begin
    Result.AddElement(TextRun(ABlock.Note));
    Exit;
  end;
  for mIndex := 0 to Length(ABlock.Entries) - 1 do
  begin
    if mIndex = TLspHoverUnitContents.cMaxPerGroup then
    begin
      Result.AddElement(TextRun(cTexts[TUnitContentsText.More].Fmt([Length(ABlock.Entries) - mIndex])));
      Exit;
    end;
    if mIndex > 0 then
    begin
      Result.AddElement(TextRun(', '));
    end;
    Result.AddElement(RefRun(ABlock.Entries[mIndex]));
  end;
end;

procedure THoverUnitContents.AddSections(ASections: TJSONArray);
var
  mBlock: TContentsBlock;
  mSection: TJSONObject;
begin
  for mBlock in BlocksOf(Self) do
  begin
    mSection := TJSONObject.Create;
    mSection.AddPair('kind', cSectionKind);
    mSection.AddPair('heading', mBlock.Heading);
    mSection.AddPair('name', GroupName(mBlock));
    mSection.AddPair('runs', BlockRuns(mBlock));
    ASections.AddElement(mSection);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Hover.UnitContents', cTexts);

end.
