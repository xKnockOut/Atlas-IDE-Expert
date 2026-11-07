unit Atlas.Common.Lsp.UnitSearch;

// Daten für das Fenster „Units suchen“ des Plugins (#777):
//   - Befehl atlas.server.units [{captions}]: alle Units aus Index und
//     Projektmodell mit Datei, Projekten, Herkunft (project, searchPath,
//     library) und Art (form, frame, dm, unit, test, inc). Kein Dateizugriff
//     außer der Frage, ob eine Formulardatei neben der Unit liegt; mit
//     captions: true zusätzlich die Caption der Formulare (#1310) aus dem Kopf
//     der Formulardatei, je Datei bis zur nächsten Änderung zwischengespeichert.
//   - Befehl atlas.server.unitPreview [uri, {form, usedBy}]: Vorschau ohne die
//     Unit im Editor zu öffnen: Kopfkommentar, Typen im interface (mit
//     Gesamtzahl typeCount), uses beider Abschnitte, Zeilenzahl, letzte
//     Änderung, Git-Zustand, Formularskizze und „Verwendet von“.
//   - Befehl atlas.server.addUses [uri, [Units], {"section"}]: „In uses
//     aufnehmen“; ohne "section" entscheidet der interface-Teil, mit
//     "interface" bzw. "implementation" gilt der Abschnitt fest („Unit
//     verwenden“, Alt+F11, #786).
// Art: Vorfahrenkette der Klassen im interface bis TForm/TCustomForm, TFrame/
// TCustomFrame oder TDataModule; ohne bekannte Kette, aber mit .dfm/.fmx ein
// Formular. Test: uses DUnitX.TestFramework bzw. TestFramework, oder die Unit
// gehört nur zu Testprojekten.
// Projekte, Index und Dateien liefert TUnitSearchContextProvider (Shell).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.Contract;

type
  /// <summary>Ein Projekt der Gruppe mit seinen Dateien.</summary>
  TUnitSearchProject = record
    /// <summary>Name ohne Endung, z. B. Atlas.IDE.Expert.</summary>
    Name: string;
    /// <summary>.dproj; '' ohne Projektdatei.</summary>
    FileName: string;
    /// <summary>Quelltexte des Projekts (Hauptdatei, DCCReference).</summary>
    Files: TArray<string>;
    /// <summary>Hauptprogramm nutzt DUnitX bzw. DUnit.</summary>
    IsTest: Boolean;
  end;

  TUnitSearchContext = record
    Units: TArray<TUnitIndex>;
    Projects: TArray<TUnitSearchProject>;
    /// <summary>Vorfahren eines Typs (Klasse) laut Index; nil wenn unbekannt.</summary>
    AncestorsOf: TFunc<string, TArray<string>>;
    /// <summary>Gibt es die Datei?</summary>
    Exists: TFunc<string, Boolean>;
    /// <summary>Inhalt einer Datei (auch offene Dokumente); '' wenn sie fehlt.</summary>
    ReadText: TFunc<string, string>;
    /// <summary>Letzte Änderung; 0 wenn unbekannt.</summary>
    Modified: TFunc<string, TDateTime>;
    /// <summary>Git-Zustand der Datei (siehe TUnitSearch.GitState); '' ohne Git oder Repository.</summary>
    GitState: TFunc<string, string>;
    /// <summary>uses-Kontext (Declaring, Namespaces) zur URI der Datei, in die „uses aufnehmen“ schreibt.</summary>
    UsesFor: TFunc<string, TUsesContext>;
  end;

  TUnitSearchContextProvider = reference to function(out AContext: TUnitSearchContext): Boolean;

  /// <summary>Komponente der Formularskizze in Pixeln des Formulars, absolut.</summary>
  TUnitSketchItem = record
    Name: string;
    TypeName: string;
    Caption: string;
    Left, Top, Width, Height: Integer;
    /// <summary>Tiefe im Komponentenbaum, 1 = direkt auf dem Formular.</summary>
    Depth: Integer;
  end;

  TUnitSketch = record
    FormClass: string;
    Caption: string;
    Width, Height: Integer;
    Items: TArray<TUnitSketchItem>;
  end;

  TUnitSearch = class
  public const
    cUnitsCommand = 'atlas.server.units';
    cPreviewCommand = 'atlas.server.unitPreview';
    cAddUsesCommand = 'atlas.server.addUses';
    /// <summary>Höchstzahl der Komponenten in der Skizze.</summary>
    cMaxSketchItems = 200;
    cMaxHeaderLines = 12;
    cMaxTypes = 40;
    cMaxUsedBy = 12;
  private type
    TCaptionEntry = record
      Modified: TDateTime;
      Caption: string;
    end;
  private
    FContextFor: TUnitSearchContextProvider;
    /// <summary>Caption je Formulardatei (Großschrift) mit dem Änderungszeitpunkt beim Lesen.</summary>
    FCaptions: TDictionary<string, TCaptionEntry>;
    function CachedCaption(const AContext: TUnitSearchContext; const AFormFile: string): string;
    function CaptionsFor(const AContext: TUnitSearchContext): TFunc<string, string>;
  public
    constructor Create(const AContextFor: TUnitSearchContextProvider);
    destructor Destroy; override;
    /// <summary>Art der Unit: form, frame, dm, test oder unit.</summary>
    class function KindOf(const AUnit: TUnitIndex; const AAncestorsOf: TFunc<string, TArray<string>>;
      AHasForm, AOnlyTestProjects: Boolean): string; static;
    /// <summary>Formulardatei neben AFileName (.dfm, dann .fmx); '' ohne.</summary>
    class function FormFileOf(const AFileName: string; const AExists: TFunc<string, Boolean>): string; static;
    /// <summary>Kommentar vor „unit …;“ ohne Kommentarzeichen, höchstens MaxHeaderLines Zeilen.</summary>
    class function HeaderComment(const AText: string): string; static;
    /// <summary>Zeilenzahl des Textes (letzte Zeile ohne Umbruch zählt mit).</summary>
    class function LineCount(const AText: string): Integer; static;
    /// <summary>Zustand aus „git status --porcelain“: clean, modified, added, deleted, renamed, untracked,
    /// conflict; '' ohne Repository (ALines = nil und AInRepo = False).</summary>
    class function GitState(const ALines: TArray<string>; AInRepo: Boolean): string; static;
    /// <summary>Caption des Wurzelobjekts einer Text-DFM/-FMX (#1310); liest nur die Eigenschaften vor dem
    /// ersten Kindobjekt. '' ohne Caption und bei binären Dateien.</summary>
    class function FormCaption(const AFormText: string): string; static;
    /// <summary>Skizze aus der Formulardatei: absolute Lage aus Left/Top samt einfachem Align.</summary>
    class function Sketch(const AFormText: string): TUnitSketch; static;
    /// <summary>Namen der Units, die AUnitName in uses haben (ohne Bibliothek), sortiert.</summary>
    class function UsedBy(const AUnits: TArray<TUnitIndex>; const AUnitName: string): TArray<string>; static;
    /// <summary>Antwort auf atlas.server.units ohne Captions.</summary>
    class function UnitsJson(const AContext: TUnitSearchContext): TJSONObject; overload; static;
    /// <summary>Antwort auf atlas.server.units; ACaptionOf liefert zur Formulardatei die Caption (#1310), nil =
    /// keine.</summary>
    class function UnitsJson(const AContext: TUnitSearchContext; const ACaptionOf: TFunc<string, string>)
      : TJSONObject; overload; static;
    /// <summary>Antwort auf atlas.server.unitPreview; AWithForm/AWithUsedBy schalten die Teile.</summary>
    class function PreviewJson(const AContext: TUnitSearchContext; const AFileName: string;
      AWithForm, AWithUsedBy: Boolean): TJSONObject; static;
    /// <summary>Antwort auf atlas.server.addUses: {edit: WorkspaceEdit oder null, added: [Namen]}.
    /// Jede Unit kommt ins interface-uses, wenn ein Bezeichner des interface-Teils aus ihr stammt,
    /// sonst ins implementation-uses; vorhandene Units entfallen.</summary>
    class function AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
      const AUses: TUsesContext): TJSONObject; overload; static;
    /// <summary>Wie oben mit festem Abschnitt ATarget (#786).</summary>
    class function AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
      const AUses: TUsesContext; ATarget: TUsesAddTarget): TJSONObject; overload; static;
    /// <summary>Argumente: [{captions: Boolean}] (optional, Standard ohne Captions).</summary>
    function ExecuteUnits(const AArguments: TJSONArray): TJSONValue;
    function ExecutePreview(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Argumente: [uri der Zieldatei, [Unit-Namen], optional {"section": "interface" |
    /// "implementation"}].</summary>
    function ExecuteAddUses(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Text.Lines;

const
  cTypeKinds: set of TIndexSymbolKind = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];

function KindName(AKind: TIndexSymbolKind): string;
begin
  case AKind of
    TIndexSymbolKind.ClassType: Result := 'class';
    TIndexSymbolKind.ObjectType: Result := 'object';
    TIndexSymbolKind.RecordType: Result := 'record';
    TIndexSymbolKind.InterfaceType: Result := 'interface';
    TIndexSymbolKind.HelperType: Result := 'helper';
    TIndexSymbolKind.EnumType: Result := 'enum';
  else
    Result := 'type';
  end;
end;

function HasUses(const AUnit: TUnitIndex; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in AUnit.InterfaceUses do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  for mName in AUnit.ImplementationUses do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TUnitSearch }

constructor TUnitSearch.Create(const AContextFor: TUnitSearchContextProvider);
begin
  inherited Create;
  FContextFor := AContextFor;
  FCaptions := TDictionary<string, TCaptionEntry>.Create;
end;

destructor TUnitSearch.Destroy;
begin
  FCaptions.Free;
  inherited;
end;

function IsObjectLine(const ATrimmed: string): Boolean;
begin
  Result := StartsText('object ', ATrimmed) or StartsText('inherited ', ATrimmed) or
    StartsText('inline ', ATrimmed);
end;

/// <summary>Erste nicht leere Zeile; Length(ALines) ohne.</summary>
function FirstContentLine(const ALines: TArray<string>): Integer;
begin
  Result := 0;
  while (Result <= High(ALines)) and (Trim(ALines[Result]) = '') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Zeile ohne Leerraum an beiden Enden; AIndent: Einrückung.</summary>
function SplitIndent(const ALine: string; out AIndent: Integer): string;
begin
  Result := TrimLeft(ALine);
  AIndent := Length(ALine) - Length(Result);
  Result := TrimRight(Result);
end;

/// <summary>Die Eigenschaften des Wurzelobjekts sind zu Ende: weniger eingerückt, oder gleich weit mit
/// Kindobjekt bzw. end.</summary>
function RootEnded(const ATrimmed: string; AIndent, ARootIndent: Integer): Boolean;
begin
  Result := (AIndent < ARootIndent) or
    ((AIndent = ARootIndent) and (IsObjectLine(ATrimmed) or SameText(ATrimmed, 'end')));
end;

/// <summary>True bei „Caption = …“; ARest beginnt mit dem Gleichheitszeichen.</summary>
function IsCaptionLine(const ATrimmed: string; out ARest: string): Boolean;
begin
  ARest := '';
  Result := StartsText('Caption', ATrimmed);
  if Result then
  begin
    ARest := TrimLeft(Copy(ATrimmed, Length('Caption') + 1, MaxInt));
    Result := StartsStr('=', ARest);
  end;
end;

/// <summary>Wert nach „Caption“; lange Werte setzt Delphi ab Zeile AIndex fort: "Caption =" allein oder Teile
/// mit "+" am Ende.</summary>
function CaptionValue(const ALines: TArray<string>; AIndex: Integer; const ARest: string): string;
var
  mValue: string;
  mIndex: Integer;
begin
  mValue := Trim(Copy(ARest, 2, MaxInt));
  mIndex := AIndex;
  while ((mValue = '') or EndsStr('+', mValue)) and (mIndex <= High(ALines)) do
  begin
    mValue := mValue + ' ' + Trim(ALines[mIndex]);
    Inc(mIndex);
  end;
  if not TStringLiterals.PlainText(mValue, Result) then
  begin
    Result := '';
  end;
end;

class function TUnitSearch.FormCaption(const AFormText: string): string;
var
  mLines: TArray<string>;
  mIndex, mIndent, mRootIndent: Integer;
  mTrimmed, mRest: string;
begin
  Result := '';
  if (AFormText = '') or TFormModel.IsBinary(AFormText) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AFormText);
  mIndex := FirstContentLine(mLines);
  if (mIndex > High(mLines)) or not IsObjectLine(Trim(mLines[mIndex])) then
  begin
    Exit;
  end;
  // Eigenschaften des Wurzelobjekts stehen vor seinen Kindobjekten und gleich weit eingerückt; tiefer
  // eingerückte Zeilen gehören zu Listen oder Collections.
  mRootIndent := -1;
  Inc(mIndex);
  while mIndex <= High(mLines) do
  begin
    mTrimmed := SplitIndent(mLines[mIndex], mIndent);
    Inc(mIndex);
    if mTrimmed = '' then
    begin
      Continue;
    end;
    if mRootIndent < 0 then
    begin
      mRootIndent := mIndent;
    end;
    if RootEnded(mTrimmed, mIndent, mRootIndent) then
    begin
      Exit;
    end;
    if (mIndent = mRootIndent) and IsCaptionLine(mTrimmed, mRest) then
    begin
      Exit(CaptionValue(mLines, mIndex, mRest));
    end;
  end;
end;

function TUnitSearch.CachedCaption(const AContext: TUnitSearchContext; const AFormFile: string): string;
var
  mKey: string;
  mModified: TDateTime;
  mEntry: TCaptionEntry;
begin
  Result := '';
  if (AFormFile = '') or not Assigned(AContext.ReadText) then
  begin
    Exit;
  end;
  mKey := UpperCase(AFormFile);
  mModified := 0;
  if Assigned(AContext.Modified) then
  begin
    mModified := AContext.Modified(AFormFile);
  end;
  System.TMonitor.Enter(FCaptions);
  try
    if (mModified <> 0) and FCaptions.TryGetValue(mKey, mEntry) and (mEntry.Modified = mModified) then
    begin
      Exit(mEntry.Caption);
    end;
  finally
    System.TMonitor.Exit(FCaptions);
  end;
  Result := FormCaption(AContext.ReadText(AFormFile));
  // Ohne bekannten Zeitpunkt nicht merken: Die Datei könnte sich unbemerkt ändern.
  if mModified = 0 then
  begin
    Exit;
  end;
  mEntry.Modified := mModified;
  mEntry.Caption := Result;
  System.TMonitor.Enter(FCaptions);
  try
    FCaptions.AddOrSetValue(mKey, mEntry);
  finally
    System.TMonitor.Exit(FCaptions);
  end;
end;

/// <summary>Art zu einem Basistyp: form, frame, dm; '' für andere.</summary>
function BaseKind(const AName: string): string;
var
  mUpper: string;
begin
  mUpper := UpperCase(AName);
  if (mUpper = 'TFORM') or (mUpper = 'TCUSTOMFORM') then
  begin
    Result := 'form';
  end
  else if (mUpper = 'TFRAME') or (mUpper = 'TCUSTOMFRAME') then
  begin
    Result := 'frame';
  end
  else if mUpper = 'TDATAMODULE' then
  begin
    Result := 'dm';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Art aus der Vorfahrenkette ab AAncestor (höchstens 16 Stufen); '' ohne bekannte Basis.</summary>
function ChainKind(const AAncestor: string; const AAncestorsOf: TFunc<string, TArray<string>>;
  ASeen: TDictionary<string, Boolean>): string;
var
  mName: string;
  mAncestors: TArray<string>;
  mDepth: Integer;
begin
  Result := '';
  mName := AAncestor;
  ASeen.Clear;
  for mDepth := 1 to 16 do
  begin
    // Qualifizierte Namen (Vcl.Forms.TForm) auf den letzten Teil kürzen.
    if Pos('.', mName) > 0 then
    begin
      mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
    end;
    Result := BaseKind(mName);
    if (Result <> '') or (mName = '') or ASeen.ContainsKey(UpperCase(mName)) or not Assigned(AAncestorsOf) then
    begin
      Exit;
    end;
    ASeen.Add(UpperCase(mName), True);
    mAncestors := AAncestorsOf(mName);
    if Length(mAncestors) = 0 then
    begin
      Exit;
    end;
    mName := mAncestors[0];
  end;
end;

class function TUnitSearch.KindOf(const AUnit: TUnitIndex; const AAncestorsOf: TFunc<string, TArray<string>>;
  AHasForm, AOnlyTestProjects: Boolean): string;
var
  mSymbol: TIndexSymbol;
  mSeen: TDictionary<string, Boolean>;
begin
  if HasUses(AUnit, 'DUnitX.TestFramework') or HasUses(AUnit, 'TestFramework') or AOnlyTestProjects then
  begin
    Exit('test');
  end;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mSymbol in AUnit.Symbols do
    begin
      if mSymbol.InInterface and (mSymbol.Container = '') and (mSymbol.Kind = TIndexSymbolKind.ClassType) and
        (Length(mSymbol.Ancestors) > 0) then
      begin
        Result := ChainKind(mSymbol.Ancestors[0], AAncestorsOf, mSeen);
        if Result <> '' then
        begin
          Exit;
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
  if AHasForm then
  begin
    Result := 'form';
  end
  else
  begin
    Result := 'unit';
  end;
end;

class function TUnitSearch.FormFileOf(const AFileName: string; const AExists: TFunc<string, Boolean>): string;
var
  mExtension: string;
begin
  Result := '';
  if not Assigned(AExists) then
  begin
    Exit;
  end;
  for mExtension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    if AExists(ChangeFileExt(AFileName, mExtension)) then
    begin
      Exit(ChangeFileExt(AFileName, mExtension));
    end;
  end;
end;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was mit einer Zeile des Kopfkommentars geschieht.</summary>
  THeaderLine = (Skip, Add, Stop);
  {$SCOPEDENUMS OFF}

/// <summary>Kommentarzeile "//" ohne Schrägstriche in AText; False für Trennlinien aus Strichen.</summary>
function LineCommentText(const ALine: string; out AText: string): Boolean;
begin
  AText := Trim(Copy(ALine, 3, MaxInt));
  // "///" wie "//" behandeln.
  while AText.StartsWith('/') do
  begin
    AText := Trim(Copy(AText, 2, MaxInt));
  end;
  Result := (AText = '') or (AText.Replace('-', '').Replace('=', '').Replace('*', '') <> '');
end;

/// <summary>Beginn eines Blockkommentars AOpen … AClose mit dem Text in AText; liefert AClose, wenn er in der
/// Zeile nicht endet, sonst ''.</summary>
function OpenBlock(const ALine, AOpen, AClose: string; out AText: string): string;
var
  mStop: Integer;
begin
  mStop := Pos(AClose, ALine);
  if mStop > 0 then
  begin
    AText := Trim(Copy(ALine, Length(AOpen) + 1, mStop - Length(AOpen) - 1));
    Result := '';
  end
  else
  begin
    AText := Trim(Copy(ALine, Length(AOpen) + 1, MaxInt));
    Result := AClose;
  end;
end;

/// <summary>Folgezeile eines offenen Blockkommentars; True, wenn er in ihr mit AClose endet.</summary>
function CloseBlock(const ALine, AClose: string; out AText: string): Boolean;
var
  mStop: Integer;
begin
  mStop := Pos(AClose, ALine);
  Result := mStop > 0;
  if Result then
  begin
    AText := Trim(Copy(ALine, 1, mStop - 1));
  end
  else
  begin
    AText := ALine;
  end;
end;

/// <summary>Ordnet eine getrimmte Zeile des Dateikopfs ein. AClose: Ende des offenen Blockkommentars, ''
/// außerhalb.</summary>
function HeaderPart(const ALine: string; AHasOutput: Boolean; var AClose: string; out APart: string): THeaderLine;
begin
  APart := '';
  Result := THeaderLine.Add;
  if AClose <> '' then
  begin
    if CloseBlock(ALine, AClose, APart) then
    begin
      AClose := '';
    end;
  end
  else if ALine = '' then
  begin
    // Leerzeilen nur zwischen Kommentaren.
    if not AHasOutput then
    begin
      Result := THeaderLine.Skip;
    end;
  end
  else if ALine.StartsWith('{$') then
  begin
    Result := THeaderLine.Skip;
  end
  else if ALine.StartsWith('//') then
  begin
    if not LineCommentText(ALine, APart) then
    begin
      Result := THeaderLine.Skip;
    end;
  end
  else if ALine.StartsWith('{') then
  begin
    AClose := OpenBlock(ALine, '{', '}', APart);
  end
  else if ALine.StartsWith('(*') then
  begin
    AClose := OpenBlock(ALine, '(*', '*)', APart);
  end
  else
  begin
    // Erstes echtes Wort: unit, program usw.; der Kopf ist vorbei.
    Result := THeaderLine.Stop;
  end;
end;

/// <summary>Zeilen ohne Leerzeilen am Ende, gekürzt auf AMax Zeilen.</summary>
function JoinHeader(const ALines: TArray<string>; AMax: Integer): string;
var
  mCount: Integer;
  mOutput: TArray<string>;
begin
  mCount := Length(ALines);
  while (mCount > 0) and (ALines[mCount - 1] = '') do
  begin
    Dec(mCount);
  end;
  mOutput := Copy(ALines, 0, Min(mCount, AMax));
  if mCount > AMax then
  begin
    mOutput[High(mOutput)] := mOutput[High(mOutput)] + ' …';
  end;
  Result := string.Join(#10, mOutput);
end;

class function TUnitSearch.HeaderComment(const AText: string): string;
var
  mLines, mOutput: TArray<string>;
  mPart, mClose: string;
  mIndex: Integer;
begin
  mLines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  mOutput := nil;
  mClose := '';
  for mIndex := 0 to High(mLines) do
  begin
    case HeaderPart(Trim(mLines[mIndex]), Length(mOutput) > 0, mClose, mPart) of
      THeaderLine.Add:
        mOutput := mOutput + [mPart];
      THeaderLine.Stop:
        Break;
    else
      // Schalter, Trennlinien und Leerzeilen vor dem ersten Kommentar entfallen.
    end;
  end;
  Result := JoinHeader(mOutput, cMaxHeaderLines);
end;

class function TUnitSearch.LineCount(const AText: string): Integer;
var
  mIndex: Integer;
begin
  if AText = '' then
  begin
    Exit(0);
  end;
  Result := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(Result);
    end;
  end;
  if AText[Length(AText)] = #10 then
  begin
    Dec(Result);
  end;
end;

/// <summary>Zustand zum Code aus „git status --porcelain“; '' für unverändert.</summary>
function CodeState(const ACode: string): string;
begin
  if ACode = '??' then
  begin
    Result := 'untracked';
  end
  else if (ACode = 'UU') or (ACode = 'AA') or (ACode = 'DD') or (Pos('U', ACode) > 0) then
  begin
    Result := 'conflict';
  end
  else if Pos('R', ACode) > 0 then
  begin
    Result := 'renamed';
  end
  else if ACode[1] = 'A' then
  begin
    Result := 'added';
  end
  else if Pos('D', ACode) > 0 then
  begin
    Result := 'deleted';
  end
  else if Pos('M', ACode) > 0 then
  begin
    Result := 'modified';
  end
  else
  begin
    Result := '';
  end;
end;

class function TUnitSearch.GitState(const ALines: TArray<string>; AInRepo: Boolean): string;
var
  mLine, mState: string;
begin
  if not AInRepo then
  begin
    Exit('');
  end;
  Result := 'clean';
  for mLine in ALines do
  begin
    if Length(mLine) >= 2 then
    begin
      mState := CodeState(Copy(mLine, 1, 2));
      if mState <> '' then
      begin
        Exit(mState);
      end;
    end;
  end;
end;

function PropertyValue(AObject: TDfmObject; const AName: string; out AValue: string): Boolean;
var
  mItem: TDfmProperty;
begin
  for mItem in AObject.Properties do
  begin
    if SameText(mItem.Name, AName) then
    begin
      AValue := mItem.Value;
      Exit(True);
    end;
  end;
  AValue := '';
  Result := False;
end;

function IntValue(AObject: TDfmObject; const AName: string; ADefault: Integer): Integer;
var
  mValue: string;
begin
  if not PropertyValue(AObject, AName, mValue) or not TryStrToInt(Trim(mValue), Result) then
  begin
    Result := ADefault;
  end;
end;

function TextValue(AObject: TDfmObject; const AName: string): string;
begin
  if not PropertyValue(AObject, AName, Result) then
  begin
    Exit('');
  end;
  Result := Trim(Result);
  // 'Text' bzw. 'Te'#39'xt': nur der einfache Fall, sonst roh gekürzt.
  if (Length(Result) >= 2) and Result.StartsWith('''') and Result.EndsWith('''') and
    (Pos('''', Copy(Result, 2, Length(Result) - 2)) = 0) then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
  if Length(Result) > 40 then
  begin
    Result := Copy(Result, 1, 40) + '…';
  end;
end;

type
  /// <summary>Rechteck der Skizze; ohne System.Types, damit Atlas.Common nichts von Windows braucht.</summary>
  TSketchBox = record
    Left, Top, Right, Bottom: Integer;
  end;

function Box(ALeft, ATop, ARight, ABottom: Integer): TSketchBox;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

/// <summary>Lage nach Align: Ausrichtung in Reihenfolge der Datei vom Rest der Fläche ARest abziehen; ohne
/// bekanntes Align bleibt AArea.</summary>
function AlignedArea(const AAlign: string; const AArea: TSketchBox; AWidth, AHeight: Integer;
  var ARest: TSketchBox): TSketchBox;
begin
  Result := AArea;
  if AAlign = 'altop' then
  begin
    Result := Box(ARest.Left, ARest.Top, ARest.Right, ARest.Top + AHeight);
    ARest.Top := Result.Bottom;
  end
  else if AAlign = 'albottom' then
  begin
    Result := Box(ARest.Left, ARest.Bottom - AHeight, ARest.Right, ARest.Bottom);
    ARest.Bottom := Result.Top;
  end
  else if AAlign = 'alleft' then
  begin
    Result := Box(ARest.Left, ARest.Top, ARest.Left + AWidth, ARest.Bottom);
    ARest.Left := Result.Right;
  end
  else if AAlign = 'alright' then
  begin
    Result := Box(ARest.Right - AWidth, ARest.Top, ARest.Right, ARest.Bottom);
    ARest.Right := Result.Left;
  end
  else if AAlign = 'alclient' then
  begin
    Result := ARest;
  end;
end;

/// <summary>Nicht sichtbare Komponenten (TTimer, TDataSource …) haben weder Lage noch Größe in der Datei.
/// </summary>
function IsVisual(AObject: TDfmObject; const AAlign: string): Boolean;
var
  mDummy: string;
begin
  Result := PropertyValue(AObject, 'Width', mDummy) or PropertyValue(AObject, 'Height', mDummy) or
    PropertyValue(AObject, 'Left', mDummy) or (AAlign <> '');
end;

function SketchItemOf(AObject: TDfmObject; const AArea: TSketchBox; ADepth: Integer): TUnitSketchItem;
begin
  Result := Default(TUnitSketchItem);
  Result.Name := AObject.Name;
  Result.TypeName := AObject.TypeName;
  Result.Caption := TextValue(AObject, 'Caption');
  if Result.Caption = '' then
  begin
    Result.Caption := TextValue(AObject, 'Text');
  end;
  Result.Left := AArea.Left;
  Result.Top := AArea.Top;
  Result.Width := Max(0, AArea.Right - AArea.Left);
  Result.Height := Max(0, AArea.Bottom - AArea.Top);
  Result.Depth := ADepth;
end;

procedure AddChildren(AParent: TDfmObject; const AClient: TSketchBox; ADepth: Integer;
  var AItems: TArray<TUnitSketchItem>);
var
  mChild: TDfmObject;
  mAlign: string;
  mRest, mArea: TSketchBox;
  mWidth, mHeight: Integer;
begin
  mRest := AClient;
  for mChild in AParent.Children do
  begin
    if Length(AItems) >= TUnitSearch.cMaxSketchItems then
    begin
      Exit;
    end;
    if mChild.Kind = TDfmObjectKind.Item then
    begin
      Continue;
    end;
    mWidth := IntValue(mChild, 'Width', IntValue(mChild, 'ExplicitWidth', 75));
    mHeight := IntValue(mChild, 'Height', IntValue(mChild, 'ExplicitHeight', 25));
    mArea.Left := AClient.Left + IntValue(mChild, 'Left', 0);
    mArea.Top := AClient.Top + IntValue(mChild, 'Top', 0);
    mArea.Right := mArea.Left + mWidth;
    mArea.Bottom := mArea.Top + mHeight;
    PropertyValue(mChild, 'Align', mAlign);
    mAlign := LowerCase(Trim(mAlign));
    mArea := AlignedArea(mAlign, mArea, mWidth, mHeight, mRest);
    if IsVisual(mChild, mAlign) then
    begin
      AItems := AItems + [SketchItemOf(mChild, mArea, ADepth)];
      AddChildren(mChild, mArea, ADepth + 1, AItems);
    end;
  end;
end;

class function TUnitSearch.Sketch(const AFormText: string): TUnitSketch;
var
  mModel: TFormModel;
  mRoot: TDfmObject;
begin
  Result := Default(TUnitSketch);
  if AFormText = '' then
  begin
    Exit;
  end;
  mModel := TFormModel.Create(AFormText);
  try
    mRoot := mModel.Document.Root;
    if mRoot = nil then
    begin
      Exit;
    end;
    Result.FormClass := mRoot.TypeName;
    Result.Caption := TextValue(mRoot, 'Caption');
    Result.Width := IntValue(mRoot, 'ClientWidth', IntValue(mRoot, 'Width', 640));
    Result.Height := IntValue(mRoot, 'ClientHeight', IntValue(mRoot, 'Height', 480));
    AddChildren(mRoot, Box(0, 0, Result.Width, Result.Height), 1, Result.Items);
  finally
    mModel.Free;
  end;
end;

class function TUnitSearch.UsedBy(const AUnits: TArray<TUnitIndex>; const AUnitName: string): TArray<string>;
var
  mItem: TUnitIndex;
  mNames: TList<string>;
begin
  mNames := TList<string>.Create;
  try
    for mItem in AUnits do
    begin
      if not mItem.Library_ and not SameText(mItem.UnitName, AUnitName) and HasUses(mItem, AUnitName) and
        not mNames.Contains(mItem.UnitName) then
      begin
        mNames.Add(mItem.UnitName);
      end;
    end;
    mNames.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareText(A, B);
      end));
    Result := mNames.ToArray;
  finally
    mNames.Free;
  end;
end;

function TUnitSearch.CaptionsFor(const AContext: TUnitSearchContext): TFunc<string, string>;
var
  mContext: TUnitSearchContext;
begin
  mContext := AContext;
  Result :=
    function(AFormFile: string): string
    begin
      Result := CachedCaption(mContext, AFormFile);
    end;
end;

class function TUnitSearch.UnitsJson(const AContext: TUnitSearchContext): TJSONObject;
begin
  Result := UnitsJson(AContext, nil);
end;

type
  /// <summary>Baut die Antwort auf atlas.server.units.</summary>
  TUnitsJsonRun = class
  private
    FContext: TUnitSearchContext;
    FCaptionOf: TFunc<string, string>;
    // Projekte je Datei (Großschrift) als Indizes in FContext.Projects.
    FOwners: TObjectDictionary<string, TList<Integer>>;
    FSeen: TDictionary<string, Boolean>;
    FItems: TJSONArray;
    function ProjectJson(AIndex: Integer): TJSONObject;
    procedure AddOwner(const AFileName: string; AIndex: Integer);
    function Projects(const AKey: string; out AOnlyTests: Boolean): TJSONArray;
    function AddEntry(const AName, AFile, AOrigin, AKind: string; AProjects: TJSONArray): TJSONObject;
    procedure AddCaption(AEntry: TJSONObject; const AKind, AOrigin, AFormFile: string);
    function MarkSeen(const AFileName: string): Boolean;
    procedure AddIndexed(const AUnit: TUnitIndex);
    procedure AddIncludes(const AUnit: TUnitIndex; const AOrigin: string);
    procedure AddMissing(const AFileName: string);
  public
    constructor Create(const AContext: TUnitSearchContext; const ACaptionOf: TFunc<string, string>);
    destructor Destroy; override;
    function Build: TJSONObject;
  end;

constructor TUnitsJsonRun.Create(const AContext: TUnitSearchContext; const ACaptionOf: TFunc<string, string>);
begin
  inherited Create;
  FContext := AContext;
  FCaptionOf := ACaptionOf;
  FOwners := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TUnitsJsonRun.Destroy;
begin
  FSeen.Free;
  FOwners.Free;
  inherited;
end;

function TUnitsJsonRun.ProjectJson(AIndex: Integer): TJSONObject;
var
  mProject: TUnitSearchProject;
  mFileName: string;
begin
  mProject := FContext.Projects[AIndex];
  Result := TJSONObject.Create;
  Result.AddPair('name', mProject.Name);
  if mProject.FileName <> '' then
  begin
    Result.AddPair('uri', TDocumentUris.FromPath(mProject.FileName));
  end;
  Result.AddPair('isTest', TJSONBool.Create(mProject.IsTest));
  for mFileName in mProject.Files do
  begin
    AddOwner(mFileName, AIndex);
  end;
end;

procedure TUnitsJsonRun.AddOwner(const AFileName: string; AIndex: Integer);
var
  mKey: string;
  mIndices: TList<Integer>;
begin
  mKey := UpperCase(AFileName);
  if not FOwners.TryGetValue(mKey, mIndices) then
  begin
    mIndices := TList<Integer>.Create;
    FOwners.Add(mKey, mIndices);
  end;
  if not mIndices.Contains(AIndex) then
  begin
    mIndices.Add(AIndex);
  end;
end;

function TUnitsJsonRun.Projects(const AKey: string; out AOnlyTests: Boolean): TJSONArray;
var
  mList: TList<Integer>;
  mIndex: Integer;
begin
  Result := TJSONArray.Create;
  AOnlyTests := False;
  if not FOwners.TryGetValue(AKey, mList) then
  begin
    Exit;
  end;
  AOnlyTests := True;
  for mIndex in mList do
  begin
    Result.Add(FContext.Projects[mIndex].Name);
    AOnlyTests := AOnlyTests and FContext.Projects[mIndex].IsTest;
  end;
end;

function TUnitsJsonRun.AddEntry(const AName, AFile, AOrigin, AKind: string; AProjects: TJSONArray): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('uri', TDocumentUris.FromPath(AFile));
  Result.AddPair('origin', AOrigin);
  Result.AddPair('kind', AKind);
  Result.AddPair('projects', AProjects);
  FItems.Add(Result);
end;

procedure TUnitsJsonRun.AddCaption(AEntry: TJSONObject; const AKind, AOrigin, AFormFile: string);
var
  mCaption: string;
begin
  // Nur Formulare außerhalb der Bibliothek (#1310): Frames und Datenmodule haben keine sichtbare Caption.
  if not Assigned(FCaptionOf) or (AKind <> 'form') or (AOrigin = 'library') or (AFormFile = '') then
  begin
    Exit;
  end;
  mCaption := FCaptionOf(AFormFile);
  if mCaption <> '' then
  begin
    AEntry.AddPair('caption', mCaption);
  end;
end;

function TUnitsJsonRun.MarkSeen(const AFileName: string): Boolean;
var
  mKey: string;
begin
  mKey := UpperCase(AFileName);
  Result := not FSeen.ContainsKey(mKey);
  if Result then
  begin
    FSeen.Add(mKey, True);
  end;
end;

procedure TUnitsJsonRun.AddIndexed(const AUnit: TUnitIndex);
var
  mKey, mOrigin, mKind, mFormFile: string;
  mOnlyTests, mInProject: Boolean;
  mProjects: TJSONArray;
begin
  // Nur Units, keine Programme oder Packages.
  if (AUnit.UnitName = '') or not SameText(ExtractFileExt(AUnit.FileName), '.pas') or
    not MarkSeen(AUnit.FileName) then
  begin
    Exit;
  end;
  mKey := UpperCase(AUnit.FileName);
  mInProject := FOwners.ContainsKey(mKey);
  if mInProject then
  begin
    mOrigin := 'project';
  end
  else if AUnit.Library_ then
  begin
    mOrigin := 'library';
  end
  else
  begin
    mOrigin := 'searchPath';
  end;
  mProjects := Projects(mKey, mOnlyTests);
  mFormFile := TUnitSearch.FormFileOf(AUnit.FileName, FContext.Exists);
  mKind := TUnitSearch.KindOf(AUnit, FContext.AncestorsOf, mFormFile <> '', mInProject and mOnlyTests);
  AddCaption(AddEntry(AUnit.UnitName, AUnit.FileName, mOrigin, mKind, mProjects), mKind, mOrigin, mFormFile);
  // Include-Dateien der Projekt-Units (#264) als eigene Einträge.
  if not AUnit.Library_ then
  begin
    AddIncludes(AUnit, mOrigin);
  end;
end;

procedure TUnitsJsonRun.AddIncludes(const AUnit: TUnitIndex; const AOrigin: string);
var
  mInclude: string;
  mOnlyTests: Boolean;
begin
  for mInclude in AUnit.Includes do
  begin
    if MarkSeen(mInclude) then
    begin
      AddEntry(ExtractFileName(mInclude), mInclude, AOrigin, 'inc', Projects(UpperCase(AUnit.FileName),
        mOnlyTests));
    end;
  end;
end;

procedure TUnitsJsonRun.AddMissing(const AFileName: string);
var
  mKind, mFormFile: string;
  mOnlyTests: Boolean;
  mProjects: TJSONArray;
begin
  if not SameText(ExtractFileExt(AFileName), '.pas') or not MarkSeen(AFileName) then
  begin
    Exit;
  end;
  mProjects := Projects(UpperCase(AFileName), mOnlyTests);
  mFormFile := TUnitSearch.FormFileOf(AFileName, FContext.Exists);
  if mOnlyTests then
  begin
    mKind := 'test';
  end
  else if mFormFile <> '' then
  begin
    mKind := 'form';
  end
  else
  begin
    mKind := 'unit';
  end;
  AddCaption(AddEntry(ChangeFileExt(ExtractFileName(AFileName), ''), AFileName, 'project', mKind, mProjects), mKind,
    'project', mFormFile);
end;

function TUnitsJsonRun.Build: TJSONObject;
var
  mProjectList: TJSONArray;
  mIndex: Integer;
  mUnit: TUnitIndex;
  mFileName: string;
begin
  Result := TJSONObject.Create;
  FItems := TJSONArray.Create;
  Result.AddPair('units', FItems);
  mProjectList := TJSONArray.Create;
  Result.AddPair('projects', mProjectList);
  for mIndex := 0 to High(FContext.Projects) do
  begin
    mProjectList.Add(ProjectJson(mIndex));
  end;
  for mUnit in FContext.Units do
  begin
    if mUnit.FileName <> '' then
    begin
      AddIndexed(mUnit);
    end;
  end;
  // Projektdateien, die (noch) nicht im Index stehen.
  for mIndex := 0 to High(FContext.Projects) do
  begin
    for mFileName in FContext.Projects[mIndex].Files do
    begin
      AddMissing(mFileName);
    end;
  end;
  Result.AddPair('count', TJSONNumber.Create(FItems.Count));
end;

class function TUnitSearch.UnitsJson(const AContext: TUnitSearchContext; const ACaptionOf: TFunc<string, string>)
  : TJSONObject;
var
  mRun: TUnitsJsonRun;
begin
  mRun := TUnitsJsonRun.Create(AContext, ACaptionOf);
  try
    Result := mRun.Build;
  finally
    mRun.Free;
  end;
end;

/// <summary>Unit zu AFileName im Index.</summary>
function FindUnit(const AUnits: TArray<TUnitIndex>; const AFileName: string; out AFound: TUnitIndex): Boolean;
var
  mItem: TUnitIndex;
begin
  for mItem in AUnits do
  begin
    if SameText(mItem.FileName, AFileName) then
    begin
      AFound := mItem;
      Exit(True);
    end;
  end;
  AFound := Default(TUnitIndex);
  Result := False;
end;

/// <summary>Kopfkommentar, Zeilenzahl, letzte Änderung und Git-Zustand.</summary>
procedure AddFileInfo(AResult: TJSONObject; const AContext: TUnitSearchContext; const AFileName: string);
var
  mText, mState: string;
  mModified: TDateTime;
begin
  mText := '';
  if Assigned(AContext.ReadText) then
  begin
    mText := AContext.ReadText(AFileName);
  end;
  AResult.AddPair('header', TUnitSearch.HeaderComment(mText));
  AResult.AddPair('lines', TJSONNumber.Create(TUnitSearch.LineCount(mText)));
  mModified := 0;
  if Assigned(AContext.Modified) then
  begin
    mModified := AContext.Modified(AFileName);
  end;
  if mModified > 0 then
  begin
    AResult.AddPair('modified', DateToISO8601(mModified, False));
  end;
  mState := '';
  if Assigned(AContext.GitState) then
  begin
    mState := AContext.GitState(AFileName);
  end;
  AResult.AddPair('git', mState);
end;

/// <summary>Typen im interface, höchstens TUnitSearch.cMaxTypes; ACount: alle.</summary>
function TypesJson(const AUnit: TUnitIndex; out ACount: Integer): TJSONArray;
var
  mSymbol: TIndexSymbol;
  mEntry: TJSONObject;
begin
  Result := TJSONArray.Create;
  ACount := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if not mSymbol.InInterface or (mSymbol.Container <> '') or not (mSymbol.Kind in cTypeKinds) then
    begin
      Continue;
    end;
    Inc(ACount);
    if Result.Count < TUnitSearch.cMaxTypes then
    begin
      mEntry := TJSONObject.Create;
      mEntry.AddPair('name', mSymbol.Name);
      mEntry.AddPair('kind', KindName(mSymbol.Kind));
      if Length(mSymbol.Ancestors) > 0 then
      begin
        mEntry.AddPair('ancestor', mSymbol.Ancestors[0]);
      end;
      Result.Add(mEntry);
    end;
  end;
end;

/// <summary>uses beider Abschnitte (#876), doppelte nur einmal.</summary>
function UsesJson(const AUnit: TUnitIndex): TJSONArray;
var
  mNames: TArray<string>;
  mName: string;
begin
  Result := TJSONArray.Create;
  mNames := nil;
  for mName in AUnit.InterfaceUses + AUnit.ImplementationUses do
  begin
    if not MatchText(mName, mNames) then
    begin
      mNames := mNames + [mName];
      Result.Add(mName);
    end;
  end;
end;

procedure AddUsedBy(AResult: TJSONObject; const AUnits: TArray<TUnitIndex>; const AUnitName: string);
var
  mNames: TArray<string>;
  mUsed: TJSONArray;
  mName: string;
begin
  mNames := TUnitSearch.UsedBy(AUnits, AUnitName);
  mUsed := TJSONArray.Create;
  for mName in mNames do
  begin
    if mUsed.Count < TUnitSearch.cMaxUsedBy then
    begin
      mUsed.Add(mName);
    end;
  end;
  AResult.AddPair('usedBy', TJSONNumber.Create(Length(mNames)));
  AResult.AddPair('usedByUnits', mUsed);
end;

function SketchJson(const ASketch: TUnitSketch): TJSONObject;
var
  mComponents: TJSONArray;
  mItem: TUnitSketchItem;
begin
  Result := TJSONObject.Create;
  Result.AddPair('class', ASketch.FormClass);
  Result.AddPair('caption', ASketch.Caption);
  Result.AddPair('width', TJSONNumber.Create(ASketch.Width));
  Result.AddPair('height', TJSONNumber.Create(ASketch.Height));
  mComponents := TJSONArray.Create;
  for mItem in ASketch.Items do
  begin
    mComponents.Add(TJSONArray.Create.Add(mItem.Name).Add(mItem.TypeName).Add(mItem.Caption).Add(mItem.Left)
      .Add(mItem.Top).Add(mItem.Width).Add(mItem.Height).Add(mItem.Depth));
  end;
  Result.AddPair('items', mComponents);
end;

class function TUnitSearch.PreviewJson(const AContext: TUnitSearchContext; const AFileName: string;
  AWithForm, AWithUsedBy: Boolean): TJSONObject;
var
  mFound: TUnitIndex;
  mHasUnit: Boolean;
  mFormFile: string;
  mSketch: TUnitSketch;
  mTypeCount: Integer;
  mTypes: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', TDocumentUris.FromPath(AFileName));
  mHasUnit := FindUnit(AContext.Units, AFileName, mFound);
  AddFileInfo(Result, AContext, AFileName);
  mTypeCount := 0;
  if mHasUnit then
  begin
    mTypes := TypesJson(mFound, mTypeCount);
    Result.AddPair('types', mTypes);
    Result.AddPair('unit', mFound.UnitName);
    Result.AddPair('uses', UsesJson(mFound));
  end
  else
  begin
    Result.AddPair('types', TJSONArray.Create);
  end;
  Result.AddPair('typeCount', TJSONNumber.Create(mTypeCount));
  if AWithUsedBy and mHasUnit then
  begin
    AddUsedBy(Result, AContext.Units, mFound.UnitName);
  end;
  mFormFile := FormFileOf(AFileName, AContext.Exists);
  if not AWithForm or (mFormFile = '') or not Assigned(AContext.ReadText) then
  begin
    Exit;
  end;
  mSketch := Sketch(AContext.ReadText(mFormFile));
  if mSketch.FormClass <> '' then
  begin
    Result.AddPair('form', SketchJson(mSketch));
  end;
end;

function TUnitSearch.ExecuteUnits(const AArguments: TJSONArray): TJSONValue;
var
  mContext: TUnitSearchContext;
  mWithCaptions: Boolean;
begin
  mWithCaptions := False;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
  begin
    TJSONObject(AArguments.Items[0]).TryGetValue<Boolean>('captions', mWithCaptions);
  end;
  if not FContextFor(mContext) then
  begin
    Exit(TJSONNull.Create);
  end;
  if not mWithCaptions then
  begin
    Exit(UnitsJson(mContext));
  end;
  Result := UnitsJson(mContext, CaptionsFor(mContext));
end;

function TUnitSearch.ExecutePreview(const AArguments: TJSONArray): TJSONValue;
var
  mContext: TUnitSearchContext;
  mWithForm, mWithUsedBy: Boolean;
  mOptions: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) then
  begin
    Exit(TJSONNull.Create);
  end;
  mWithForm := True;
  mWithUsedBy := True;
  if (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject) then
  begin
    mOptions := TJSONObject(AArguments.Items[1]);
    mOptions.TryGetValue<Boolean>('form', mWithForm);
    mOptions.TryGetValue<Boolean>('usedBy', mWithUsedBy);
  end;
  if not FContextFor(mContext) then
  begin
    Exit(TJSONNull.Create);
  end;
  Result := PreviewJson(mContext, TDocumentUris.ToPath(AArguments.Items[0].Value), mWithForm, mWithUsedBy);
end;

class function TUnitSearch.AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
  const AUses: TUsesContext): TJSONObject;
begin
  Result := AddUsesJson(AUri, AText, AUnits, AUses, TUsesAddTarget.Auto);
end;

class function TUnitSearch.AddUsesJson(const AUri, AText: string; const AUnits: TArray<string>;
  const AUses: TUsesContext; ATarget: TUsesAddTarget): TJSONObject;
var
  mEdits: TArray<TRuleEdit>;
  mEdit: TRuleEdit;
  mAdded: TArray<string>;
  mName, mLineBreak: string;
  mChanges, mWorkspaceEdit, mItem: TJSONObject;
  mList, mAddedList: TJSONArray;
begin
  Result := TJSONObject.Create;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mAddedList := TJSONArray.Create;
  if (AText <> '') and TUsesActions.AddUnits(TPascalLexer.Tokenize(AText),
    TUsesAddRequest.Create(AUnits, AUses.Declaring, AUses.Namespaces, mLineBreak).WithTarget(ATarget), mEdits,
      mAdded) then
  begin
    mList := TJSONArray.Create;
    for mEdit in mEdits do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
      mItem.AddPair('newText', mEdit.NewText);
      mList.Add(mItem);
    end;
    mChanges := TJSONObject.Create;
    mChanges.AddPair(AUri, mList);
    mWorkspaceEdit := TJSONObject.Create;
    mWorkspaceEdit.AddPair('changes', mChanges);
    Result.AddPair('edit', mWorkspaceEdit);
    for mName in mAdded do
    begin
      mAddedList.Add(mName);
    end;
  end
  else
  begin
    Result.AddPair('edit', TJSONNull.Create);
  end;
  Result.AddPair('added', mAddedList);
end;

/// <summary>Namen aus dem Array, nur Zeichenketten.</summary>
function UnitNames(AArray: TJSONArray): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  for mValue in AArray do
  begin
    if mValue is TJSONString then
    begin
      Result := Result + [mValue.Value];
    end;
  end;
end;

/// <summary>Abschnitt aus {"section": "interface" | "implementation"}; sonst Auto.</summary>
function TargetOf(AOptions: TJSONValue): TUsesAddTarget;
var
  mSection: TJSONValue;
begin
  Result := TUsesAddTarget.Auto;
  if not (AOptions is TJSONObject) then
  begin
    Exit;
  end;
  mSection := TJSONObject(AOptions).GetValue('section');
  if not (mSection is TJSONString) then
  begin
    Exit;
  end;
  if SameText(mSection.Value, 'interface') then
  begin
    Result := TUsesAddTarget.Interface_;
  end
  else if SameText(mSection.Value, 'implementation') then
  begin
    Result := TUsesAddTarget.Implementation_;
  end;
end;

function TUnitSearch.ExecuteAddUses(const AArguments: TJSONArray): TJSONValue;
var
  mContext: TUnitSearchContext;
  mUsesContext: TUsesContext;
  mUnits: TArray<string>;
  mUri: string;
  mTarget: TUsesAddTarget;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONArray) then
  begin
    Exit(TJSONNull.Create);
  end;
  mUnits := UnitNames(TJSONArray(AArguments.Items[1]));
  if not FContextFor(mContext) or not Assigned(mContext.ReadText) then
  begin
    Exit(TJSONNull.Create);
  end;
  mUri := AArguments.Items[0].Value;
  mUsesContext := Default(TUsesContext);
  if Assigned(mContext.UsesFor) then
  begin
    mUsesContext := mContext.UsesFor(mUri);
  end;
  mTarget := TUsesAddTarget.Auto;
  if AArguments.Count > 2 then
  begin
    mTarget := TargetOf(AArguments.Items[2]);
  end;
  Result := AddUsesJson(mUri, mContext.ReadText(TDocumentUris.ToPath(mUri)), mUnits, mUsesContext, mTarget);
end;

end.
