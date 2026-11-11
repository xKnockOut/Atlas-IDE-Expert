unit Atlas.Common.Rules.Builtin.DfmProperties;

// Eigenschaftsregeln für Formulardateien (#309), Regel dfm-property: Vorgaben
// für Komponenten-Properties aus "dfmPropertyRules" in atlas.json, z. B. alle
// TLabel mit Transparent = True oder kein Formular mit Position = poDesigned.
//
// Wie die übrigen DFM-Regeln liest die Regel TRuleContext.FormText (#123) über
// das Formularmodell (#267) und meldet in der Unit: am Feld der Komponente bzw.
// an der Formularklasse. Ist eine Property nicht gespeichert, gilt ihr default
// aus der Deklaration in der Klasse bzw. ihren Vorfahren (ohne default: False,
// 0, [] oder ''). Objekte aus dem Vorfahrenformular (inherited) werden nur
// gemeldet, wenn dieses Formular den Wert selbst setzt; sonst gehört der
// Verstoß zum Vorfahren. Verschachtelte Pfade (Font.Name) folgen dem Typ der
// Zwischen-Property (TFont); hat eine Property im Pfad "stored" mit einer
// Funktion oder False, ist der nicht gespeicherte Wert unbekannt und die Regel
// schweigt.
//
// Schnellkorrektur (#309): Mit bekannter Formulardatei (TRuleContext.FormFile)
// ändert sie die Formulardatei: Sollwert setzen (vorhandenen Wert ersetzen oder
// eine Zeile nach den Properties des Objekts einfügen), Set-Element ergänzen
// bzw. entfernen, leeren. Für <> und notEmpty gibt es keinen eindeutigen
// Sollwert, also keine Korrektur. fix: auto macht sie sicher (source.fixAll),
// none unterdrückt sie. Binäre Formulare werden nicht korrigiert.
//
// ConfigurationIssues meldet Regeln mit unbekannter Klasse oder Property für
// atlas.json (Abnahme #309), sobald der Index die Klasse kennen müsste.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TDfmPropertyCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Erfüllt der Ist-Wert AActual die Bedingung ACondition mit dem Sollwert AExpected?</summary>
    class function Satisfies(ACondition: TDfmCondition; const AActual, AExpected: string): Boolean; static;
    /// <summary>Wert nach "default" in einer Property-Deklaration; False ohne Angabe.</summary>
    class function DeclaredDefault(const ADeclaration: string; out AValue: string): Boolean; static;
    /// <summary>Regeln aus ARules, deren Klasse oder Property AIndex nicht kennt, als Meldungen an
    /// ClassRange bzw. PropertyRange (Warnungen in atlas.json). Ohne Index keine. AReadFile liest die
    /// Quellen des Index für Typ und default der Properties; nil = nur Namen prüfen.</summary>
    class function ConfigurationIssues(const ARules: TArray<TDfmPropertyRule>; const AIndex: ISymbolIndex;
      const AReadFile: TRuleFileReader): TArray<TConfigurationIssue>; static;
    /// <summary>Wert als DFM-Text: Strings in Hochkommas, Zeichen außerhalb ASCII als #Code.</summary>
    class function DfmString(const AValue: string): string; static;
  end;

procedure RegisterDfmPropertyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDfmPropertiesText = (Title, ShouldBe, MustNotBe, ShouldContain, MustNotContain, ShouldBeEmpty, MustNotBeEmpty,
    SetInForm, AddTo, RemoveFrom, ClearInForm, UnknownClass, NoProperty);

const
  cTexts: array[TDfmPropertiesText] of TAtlasText = (
    (De: 'Komponenten-Property weicht von einer Eigenschaftsregel aus atlas.json ab';
     En: 'Component property differs from a property rule in atlas.json'),
    (De: '%s soll %s sein, ist %s'; En: '%s should be %s, is %s'),
    (De: '%s darf nicht %s sein'; En: '%s must not be %s'),
    (De: '%s soll %s enthalten, ist %s'; En: '%s should contain %s, is %s'),
    (De: '%s darf %s nicht enthalten'; En: '%s must not contain %s'),
    (De: '%s soll leer sein, ist %s'; En: '%s should be empty, is %s'),
    (De: '%s darf nicht leer sein'; En: '%s must not be empty'),
    (De: '%s = %s in der Formulardatei setzen'; En: 'Set %s = %s in the form file'),
    (De: '%s in %s ergänzen'; En: 'Add %s to %s'),
    (De: '%s aus %s entfernen'; En: 'Remove %s from %s'),
    (De: '%s in der Formulardatei leeren'; En: 'Clear %s in the form file'),
    (De: 'Klasse "%s" ist im Index unbekannt; die Eigenschaftsregel greift nie';
     En: 'Class "%s" is unknown in the index; the property rule never applies'),
    (De: '%s hat keine Property "%s"; die Eigenschaftsregel greift nie';
     En: '%s has no property "%s"; the property rule never applies'));

{$SCOPEDENUMS OFF}

const
  cMaxDepth = 30;
  // Typ der ersten Property-Deklaration, auch mit Index: property Items[I: Integer]: string.
  cPropertyTypePattern = '\bproperty\s+\w+\s*(?:\[[^\]]*\])?\s*:\s*([\w.]+)';
  cDefaultPattern = '\bdefault\s+([^;]+?)\s*;';
  cStoredPattern = '\bstored\s+([\w.]+)';
  cStringTypes: array[0..6] of string = ('string', 'UnicodeString', 'WideString', 'AnsiString', 'TCaption',
    'TFontName', 'TFileName');

/// <summary>Wert nach "default" in ADeclaration über das kompilierte Muster ARegEx.</summary>
function DefaultOf(const ARegEx: TRegEx; const ADeclaration: string; out AValue: string): Boolean;
var
  mMatch: TMatch;
begin
  mMatch := ARegEx.Match(ADeclaration);
  Result := mMatch.Success;
  if Result then
  begin
    AValue := Trim(mMatch.Groups[1].Value);
  end
  else
  begin
    AValue := '';
  end;
end;

type
  /// <summary>Was die Deklarationen einer Property über ihren nicht gespeicherten Wert sagen.</summary>
  TPropertyInfo = record
    /// <summary>Die Property ist in der Klasse oder einem Vorfahren deklariert.</summary>
    Found: Boolean;
    /// <summary>Typ aus der ersten Deklaration mit Typ; '' ohne.</summary>
    TypeName: string;
    HasDefault: Boolean;
    DefaultValue: string;
    NoDefault: Boolean;
    /// <summary>"stored" mit Funktion oder False: Der nicht gespeicherte Wert ist unbekannt.</summary>
    StoredUnknown: Boolean;
  end;

  /// <summary>Ein Prüflauf: Klassenketten und Property-Deklarationen über den Index.</summary>
  TPropertyChecker = class
  private
    FContext: TRuleContext;
    FUnit: TUnitIndex;
    FLines: TDictionary<string, TArray<string>>;
    // Je Prüfung einmal kompiliert. TRegEx hält Zustand und ist nicht
    // threadsicher; Regeln laufen parallel, daher keine globale Instanz.
    FPropertyType: TRegEx;
    FDefault: TRegEx;
    FStored: TRegEx;
    function FileLines(const AFileName: string): TArray<string>;
    function DeclarationText(const ALocation: TSymbolLocation): string;
    /// <summary>Symbole AName aus der geprüften Unit (FileName '') und dem Index.</summary>
    function Members(const AName: string): TArray<TSymbolLocation>;
    /// <summary>Die Property AName, wie AClassName selbst sie deklariert.</summary>
    function DeclaredIn(const AClassName, AName: string; out AMember: TSymbolLocation): Boolean;
    /// <summary>stored, nodefault und default aus ADeclaration in AInfo übernehmen; ADecided: eine Angabe
    /// gefunden.</summary>
    procedure ReadDirectives(const ADeclaration: string; var AInfo: TPropertyInfo; var ADecided: Boolean);
    /// <summary>Deklarationen von AName in AClassName und den Vorfahren, die jüngste zuerst.</summary>
    function PropertyInfo(const AClassName, AName: string): TPropertyInfo;
    /// <summary>Angaben zum letzten Teil von AParts (Font.Name): über den Typ jeder Zwischen-Property zur
    /// Klasse des letzten Teils; False, wenn eine Zwischen-Property unbekannt oder nicht gespeichert ist.
    /// </summary>
    function PathInfo(const AClassName: string; const AParts: TArray<string>; out AInfo: TPropertyInfo): Boolean;
  public
    /// <summary>AUnit: die geprüfte Unit; ihre Klassen (z. B. die Formularklasse) stehen evtl. nicht im
    /// Index.</summary>
    constructor Create(const AContext: TRuleContext; const AUnit: TUnitIndex);
    destructor Destroy; override;
    function FindClass(const AName: string; out ALocation: TSymbolLocation): Boolean;
    function IsClassOrDescendant(const AClassName, ABase: string; ADescendants: Boolean): Boolean;
    /// <summary>Wert der nicht gespeicherten Property APath (auch Font.Name) von AClassName; False, wenn
    /// er unbekannt ist. ATypeName: Typ der letzten Property, '' wenn unbekannt.</summary>
    function DefaultValue(const AClassName, APath: string; out AValue, ATypeName: string): Boolean;
    /// <summary>Gibt es APath (auch Font.Name) an AClassName? AMissing: der erste unbekannte Teil.</summary>
    function HasProperty(const AClassName, APath: string; out AMissing: string): Boolean;
  end;

{ TPropertyChecker }

constructor TPropertyChecker.Create(const AContext: TRuleContext; const AUnit: TUnitIndex);
begin
  inherited Create;
  FContext := AContext;
  FUnit := AUnit;
  FLines := TDictionary<string, TArray<string>>.Create;
  FPropertyType := TRegEx.Create(cPropertyTypePattern, [roIgnoreCase, roCompiled]);
  FDefault := TRegEx.Create(cDefaultPattern, [roIgnoreCase, roCompiled]);
  FStored := TRegEx.Create(cStoredPattern, [roIgnoreCase, roCompiled]);
end;

destructor TPropertyChecker.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TPropertyChecker.FileLines(const AFileName: string): TArray<string>;
var
  mData: TBytes;
  mText: string;
  mFormat: TFileFormat;
begin
  if FLines.TryGetValue(UpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  // '' steht für die geprüfte Unit selbst.
  if AFileName = '' then
  begin
    Result := FContext.Text.Replace(#13#10, #10).Split([#10]);
  end
  else if Assigned(FContext.ReadFile) and FContext.ReadFile(AFileName, mData) then
  begin
    // Dieselbe Erkennung wie überall (#1327): BOM, sonst nur ganz gültiges UTF-8 als UTF-8, sonst ANSI.
    mText := TFileEncoding.Decode(mData, mFormat);
    Result := mText.Replace(#13#10, #10).Split([#10]);
  end;
  FLines.Add(UpperCase(AFileName), Result);
end;

function TPropertyChecker.FindClass(const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  mLocation: TSymbolLocation;
  mSymbol: TIndexSymbol;
begin
  for mSymbol in FUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Container = '') and SameText(mSymbol.Name, AName) then
    begin
      ALocation.UnitName := FUnit.UnitName;
      ALocation.FileName := '';
      ALocation.Symbol := mSymbol;
      Exit(True);
    end;
  end;
  if FContext.Index = nil then
  begin
    Exit(False);
  end;
  for mLocation in FContext.Index.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
    begin
      ALocation := mLocation;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TPropertyChecker.IsClassOrDescendant(const AClassName, ABase: string; ADescendants: Boolean): Boolean;
var
  mName: string;
  mLocation: TSymbolLocation;
  mDepth: Integer;
begin
  if SameText(AClassName, ABase) then
  begin
    Exit(True);
  end;
  Result := False;
  if not ADescendants then
  begin
    Exit;
  end;
  mName := AClassName;
  for mDepth := 1 to cMaxDepth do
  begin
    if not FindClass(mName, mLocation) or (Length(mLocation.Symbol.Ancestors) = 0) then
    begin
      Exit;
    end;
    mName := mLocation.Symbol.Ancestors[0];
    if SameText(mName, ABase) then
    begin
      Exit(True);
    end;
  end;
end;

function TPropertyChecker.Members(const AName: string): TArray<TSymbolLocation>;
var
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  Result := nil;
  for mSymbol in FUnit.Symbols do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      mLocation.UnitName := FUnit.UnitName;
      mLocation.FileName := '';
      mLocation.Symbol := mSymbol;
      Result := Result + [mLocation];
    end;
  end;
  if FContext.Index <> nil then
  begin
    Result := Result + FContext.Index.FindSymbols(AName);
  end;
end;

function TPropertyChecker.DeclarationText(const ALocation: TSymbolLocation): string;
var
  mLines: TArray<string>;
  mLine: Integer;
begin
  Result := '';
  mLines := FileLines(ALocation.FileName);
  for mLine := ALocation.Symbol.Range.StartPos.Line to ALocation.Symbol.Range.EndPos.Line do
  begin
    if (mLine >= 0) and (mLine <= High(mLines)) then
    begin
      Result := Result + ' ' + Trim(mLines[mLine]);
    end;
  end;
  Result := Trim(Result);
end;

function TPropertyChecker.DeclaredIn(const AClassName, AName: string; out AMember: TSymbolLocation): Boolean;
var
  mMember: TSymbolLocation;
begin
  for mMember in Members(AName) do
  begin
    if (mMember.Symbol.Kind = TIndexSymbolKind.Property_) and SameText(mMember.Symbol.Container, AClassName) then
    begin
      AMember := mMember;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TPropertyChecker.ReadDirectives(const ADeclaration: string; var AInfo: TPropertyInfo;
  var ADecided: Boolean);
var
  mMatch: TMatch;
begin
  mMatch := FStored.Match(ADeclaration);
  if mMatch.Success then
  begin
    AInfo.StoredUnknown := not SameText(mMatch.Groups[1].Value, 'True');
    ADecided := True;
  end;
  if ContainsText(ADeclaration, 'nodefault') then
  begin
    AInfo.NoDefault := True;
    ADecided := True;
  end
  else if DefaultOf(FDefault, ADeclaration, AInfo.DefaultValue) then
  begin
    AInfo.HasDefault := True;
    ADecided := True;
  end;
end;

function TPropertyChecker.PropertyInfo(const AClassName, AName: string): TPropertyInfo;
var
  mName, mDeclaration: string;
  mLocation, mMember: TSymbolLocation;
  mDepth: Integer;
  mMatch: TMatch;
  mDecided: Boolean;
begin
  Result := Default(TPropertyInfo);
  mDecided := False;
  mName := AClassName;
  for mDepth := 1 to cMaxDepth do
  begin
    if not FindClass(mName, mLocation) then
    begin
      Exit;
    end;
    if DeclaredIn(mName, AName, mMember) then
    begin
      Result.Found := True;
      mDeclaration := DeclarationText(mMember);
      // Die jüngste Angabe gilt; eine Hochstufung ohne Angaben (property X;) erbt sie.
      if not mDecided then
      begin
        ReadDirectives(mDeclaration, Result, mDecided);
      end;
      // Typ steht nur in der ersten Deklaration; eine Hochstufung (property X;) erbt ihn.
      mMatch := FPropertyType.Match(mDeclaration);
      if mMatch.Success then
      begin
        Result.TypeName := mMatch.Groups[1].Value;
        Exit;
      end;
    end;
    if Length(mLocation.Symbol.Ancestors) = 0 then
    begin
      Exit;
    end;
    mName := mLocation.Symbol.Ancestors[0];
  end;
end;

function TPropertyChecker.PathInfo(const AClassName: string; const AParts: TArray<string>;
  out AInfo: TPropertyInfo): Boolean;
var
  mName: string;
  mIndex: Integer;
begin
  mName := AClassName;
  for mIndex := 0 to High(AParts) - 1 do
  begin
    AInfo := PropertyInfo(mName, AParts[mIndex]);
    // Nicht gespeichertes Objekt (stored IsFontStored, ParentFont): Werte kommen von anderswo.
    if not AInfo.Found or (AInfo.TypeName = '') or AInfo.StoredUnknown then
    begin
      Exit(False);
    end;
    mName := AInfo.TypeName;
  end;
  AInfo := PropertyInfo(mName, AParts[High(AParts)]);
  Result := True;
end;

/// <summary>Ohne default speichert die VCL alles außer dem Nullwert des Typs ATypeName; False, wenn er
/// unbekannt ist.</summary>
function ZeroValue(const ATypeName: string; out AValue: string): Boolean;
begin
  Result := True;
  AValue := '';
  if SameText(ATypeName, 'Boolean') then
  begin
    AValue := 'False';
  end
  else if MatchText(ATypeName, ['Integer', 'Cardinal', 'Byte', 'Word', 'SmallInt', 'ShortInt', 'Int64',
    'UInt64', 'NativeInt', 'NativeUInt', 'LongInt', 'LongWord', 'TColor']) then
  begin
    AValue := '0';
  end
  else
  begin
    Result := MatchText(ATypeName, cStringTypes);
  end;
end;

function TPropertyChecker.DefaultValue(const AClassName, APath: string; out AValue, ATypeName: string): Boolean;
var
  mParts: TArray<string>;
  mInfo: TPropertyInfo;
begin
  Result := False;
  AValue := '';
  ATypeName := '';
  mParts := APath.Split(['.']);
  if (Length(mParts) = 0) or not PathInfo(AClassName, mParts, mInfo) then
  begin
    Exit;
  end;
  ATypeName := mInfo.TypeName;
  if not mInfo.Found or mInfo.StoredUnknown or mInfo.NoDefault then
  begin
    Exit;
  end;
  if mInfo.HasDefault then
  begin
    AValue := mInfo.DefaultValue;
    Result := True;
  end
  else
  begin
    Result := ZeroValue(mInfo.TypeName, AValue);
  end;
end;

function TPropertyChecker.HasProperty(const AClassName, APath: string; out AMissing: string): Boolean;
var
  mName, mPart: string;
  mInfo: TPropertyInfo;
  mLocation: TSymbolLocation;
begin
  AMissing := '';
  mName := AClassName;
  for mPart in APath.Split(['.']) do
  begin
    // Typ ohne Klasse im Index (z. B. ein Aufzählungstyp vor dem letzten Teil): nicht weiter prüfbar.
    if not FindClass(mName, mLocation) then
    begin
      Exit(True);
    end;
    mInfo := PropertyInfo(mName, mPart);
    if not mInfo.Found then
    begin
      AMissing := mPart;
      Exit(False);
    end;
    mName := mInfo.TypeName;
    if mName = '' then
    begin
      Exit(True);
    end;
  end;
  Result := True;
end;

{ TDfmPropertyCheckRule }

function TDfmPropertyCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-property', TRuleSeverity.Warning,
    cTexts[TDfmPropertiesText.Title].Text);
end;

class function TDfmPropertyCheckRule.DeclaredDefault(const ADeclaration: string; out AValue: string): Boolean;
begin
  Result := DefaultOf(TRegEx.Create(cDefaultPattern, [roIgnoreCase]), ADeclaration, AValue);
end;

function Unquote(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
  end;
end;

function IsSet(const AValue: string): Boolean;
begin
  Result := StartsStr('[', Trim(AValue)) and EndsStr(']', Trim(AValue));
end;

function SetElements(const AValue: string): TArray<string>;
var
  mInner, mElement: string;
begin
  Result := nil;
  mInner := Trim(AValue);
  mInner := Copy(mInner, 2, Length(mInner) - 2);
  for mElement in mInner.Split([',']) do
  begin
    if Trim(mElement) <> '' then
    begin
      Result := Result + [Trim(mElement)];
    end;
  end;
end;

function IsEmptyValue(const AValue: string): Boolean;
begin
  Result := (Trim(AValue) = '') or (Unquote(AValue) = '') or (IsSet(AValue) and (Length(SetElements(AValue)) = 0));
end;

function SameValue(const AActual, AExpected: string): Boolean;
var
  mElement: string;
  mActual, mExpected: TArray<string>;
begin
  if IsSet(AActual) and IsSet(AExpected) then
  begin
    mActual := SetElements(AActual);
    mExpected := SetElements(AExpected);
    if Length(mActual) <> Length(mExpected) then
    begin
      Exit(False);
    end;
    for mElement in mExpected do
    begin
      if not MatchText(mElement, mActual) then
      begin
        Exit(False);
      end;
    end;
    Exit(True);
  end;
  Result := SameText(Unquote(AActual), Unquote(AExpected));
end;

function ContainsValue(const AActual, AExpected: string): Boolean;
begin
  if IsSet(AActual) then
  begin
    Result := MatchText(Trim(AExpected), SetElements(AActual));
  end
  else
  begin
    Result := ContainsText(Unquote(AActual), Unquote(AExpected));
  end;
end;

class function TDfmPropertyCheckRule.Satisfies(ACondition: TDfmCondition; const AActual, AExpected: string): Boolean;
begin
  case ACondition of
    TDfmCondition.Equal:
      Result := SameValue(AActual, AExpected);
    TDfmCondition.NotEqual:
      Result := not SameValue(AActual, AExpected);
    TDfmCondition.Contains:
      Result := ContainsValue(AActual, AExpected);
    TDfmCondition.NotContains:
      Result := not ContainsValue(AActual, AExpected);
    TDfmCondition.Empty:
      Result := IsEmptyValue(AActual);
  else
    Result := not IsEmptyValue(AActual);
  end;
end;

function DefaultMessage(const ARule: TDfmPropertyRule; const AObject: TDfmObject; const AActual: string): string;
var
  mActual: string;
begin
  mActual := AActual;
  if mActual = '' then
  begin
    mActual := '''''';
  end;
  case ARule.Condition of
    TDfmCondition.Equal:
      Result := cTexts[TDfmPropertiesText.ShouldBe].Fmt([ARule.PropertyPath, ARule.Value, mActual]);
    TDfmCondition.NotEqual:
      Result := cTexts[TDfmPropertiesText.MustNotBe].Fmt([ARule.PropertyPath, ARule.Value]);
    TDfmCondition.Contains:
      Result := cTexts[TDfmPropertiesText.ShouldContain].Fmt([ARule.PropertyPath, ARule.Value, mActual]);
    TDfmCondition.NotContains:
      Result := cTexts[TDfmPropertiesText.MustNotContain].Fmt([ARule.PropertyPath, ARule.Value]);
    TDfmCondition.Empty:
      Result := cTexts[TDfmPropertiesText.ShouldBeEmpty].Fmt([ARule.PropertyPath, mActual]);
  else
    Result := cTexts[TDfmPropertiesText.MustNotBeEmpty].Fmt([ARule.PropertyPath]);
  end;
  Result := Format('%s (%s): %s', [AObject.Name, AObject.TypeName, Result]);
end;

function IsExcluded(const ARule: TDfmPropertyRule; const ARelativePath: string): Boolean;
var
  mPattern: string;
begin
  if ARelativePath = '' then
  begin
    Exit(False);
  end;
  for mPattern in ARule.Exclude do
  begin
    if MatchesGlob(mPattern, ARelativePath) or MatchesGlob(mPattern, ChangeFileExt(ARelativePath, '.dfm')) or
      MatchesGlob(mPattern, ChangeFileExt(ARelativePath, '.fmx')) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure CollectObjects(AObject: TDfmObject; var AObjects: TArray<TDfmObject>);
var
  mChild: TDfmObject;
begin
  if (AObject.Kind <> TDfmObjectKind.Item) and (AObject.TypeName <> '') then
  begin
    AObjects := AObjects + [AObject];
  end;
  for mChild in AObject.Children do
  begin
    CollectObjects(mChild, AObjects);
  end;
end;

/// <summary>Zeichen ACh an den DFM-Text AResult anhängen; AQuoted: AResult endet in Hochkommas.</summary>
procedure AppendDfmChar(var AResult: string; var AQuoted: Boolean; ACh: Char);
begin
  if (Ord(ACh) >= 32) and (Ord(ACh) < 127) then
  begin
    if not AQuoted then
    begin
      AResult := AResult + '''';
    end;
    AQuoted := True;
    if ACh = '''' then
    begin
      AResult := AResult + '''''';
    end
    else
    begin
      AResult := AResult + ACh;
    end;
  end
  else
  begin
    if AQuoted then
    begin
      AResult := AResult + '''';
    end;
    AQuoted := False;
    AResult := AResult + '#' + IntToStr(Ord(ACh));
  end;
end;

class function TDfmPropertyCheckRule.DfmString(const AValue: string): string;
var
  mCh: Char;
  mQuoted: Boolean;
begin
  // Wie die IDE: druckbares ASCII in Hochkommas, alles andere als #Code.
  Result := '';
  mQuoted := False;
  for mCh in AValue do
  begin
    AppendDfmChar(Result, mQuoted, mCh);
  end;
  if mQuoted then
  begin
    Result := Result + '''';
  end;
  if Result = '' then
  begin
    Result := '''''';
  end;
end;

function IsIdentifierLike(const AValue: string): Boolean;
var
  mCh: Char;
begin
  Result := AValue <> '';
  for mCh in AValue do
  begin
    if not CharInSet(mCh, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', '$']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Sollwert als DFM-Text. AStringType: die Property ist ein String (gespeichert in Hochkommas
/// oder vom Typ string); sonst bleiben Bezeichner, Zahlen und Mengen, wie sie sind.</summary>
function DfmValue(const AValue: string; AStringType: Boolean): string;
begin
  Result := Trim(AValue);
  if StartsStr('''', Result) or StartsStr('#', Result) then
  begin
    Exit;
  end;
  if AStringType or not (IsSet(Result) or IsIdentifierLike(Result)) then
  begin
    Result := TDfmPropertyCheckRule.DfmString(AValue);
  end;
end;

function JoinSet(const AElements: TArray<string>): string;
begin
  Result := '[' + string.Join(', ', AElements) + ']';
end;

/// <summary>Menge AActual ohne das Element AElement.</summary>
function SetWithout(const AActual, AElement: string): string;
var
  mKept: TArray<string>;
  mElement: string;
begin
  mKept := nil;
  for mElement in SetElements(AActual) do
  begin
    if not SameText(mElement, AElement) then
    begin
      mKept := mKept + [mElement];
    end;
  end;
  Result := JoinSet(mKept);
end;

/// <summary>Leerer Wert für AActual: [] bei Mengen, '' bei Strings; False, wenn er unbekannt ist.</summary>
function EmptyValue(const AActual: string; AStringType: Boolean; out AValue: string): Boolean;
begin
  Result := True;
  if IsSet(AActual) then
  begin
    AValue := '[]';
  end
  else if AStringType or StartsStr('''', Trim(AActual)) or StartsStr('#', Trim(AActual)) then
  begin
    AValue := '''''';
  end
  else
  begin
    AValue := '';
    Result := False;
  end;
end;

/// <summary>Neuer Wert, der die Regel erfüllt; False, wenn es keinen eindeutigen gibt.</summary>
function TargetValue(const ARule: TDfmPropertyRule; const AActual: string; AStringType: Boolean;
  out AValue, ATitle: string): Boolean;
begin
  Result := True;
  AValue := '';
  ATitle := '';
  case ARule.Condition of
    TDfmCondition.Equal:
      begin
        AValue := DfmValue(ARule.Value, AStringType);
        ATitle := cTexts[TDfmPropertiesText.SetInForm].Fmt([ARule.PropertyPath, AValue]);
      end;
    TDfmCondition.Contains:
      begin
        Result := IsSet(AActual);
        AValue := JoinSet(SetElements(AActual) + [Trim(ARule.Value)]);
        ATitle := cTexts[TDfmPropertiesText.AddTo].Fmt([Trim(ARule.Value), ARule.PropertyPath]);
      end;
    TDfmCondition.NotContains:
      begin
        Result := IsSet(AActual);
        AValue := SetWithout(AActual, Trim(ARule.Value));
        ATitle := cTexts[TDfmPropertiesText.RemoveFrom].Fmt([Trim(ARule.Value), ARule.PropertyPath]);
      end;
    TDfmCondition.Empty:
      begin
        Result := EmptyValue(AActual, AStringType, AValue);
        ATitle := cTexts[TDfmPropertiesText.ClearInForm].Fmt([ARule.PropertyPath]);
      end;
  else
    // <> und notEmpty: kein eindeutiger Sollwert.
    Result := False;
  end;
end;

function LeadingSpaces(const ALine: string): string;
var
  mCount: Integer;
begin
  mCount := 0;
  while (mCount < Length(ALine)) and CharInSet(ALine[mCount + 1], [' ', #9]) do
  begin
    Inc(mCount);
  end;
  Result := Copy(ALine, 1, mCount);
end;

/// <summary>Edit in der Formulardatei: eine Zeile AName = AValue nach den Properties des Objekts einfügen.
/// </summary>
function InsertEdit(const AFormLines: TArray<string>; const ALineBreak: string; AObject: TDfmObject;
  const AName, AValue: string): TRuleEdit;
var
  mItem: TDfmProperty;
  mLine: Integer;
  mIndent: string;
begin
  // Hinter der letzten Property, vor den Kindobjekten; ohne Properties hinter der Kopfzeile.
  mLine := AObject.TypeRange.EndPos.Line;
  for mItem in AObject.Properties do
  begin
    if mItem.ValueRange.EndPos.Line > mLine then
    begin
      mLine := mItem.ValueRange.EndPos.Line;
    end;
  end;
  mIndent := '';
  if (AObject.Range.StartPos.Line >= 0) and (AObject.Range.StartPos.Line <= High(AFormLines)) then
  begin
    mIndent := LeadingSpaces(AFormLines[AObject.Range.StartPos.Line]);
  end;
  Result := TRuleEdit.Create(TTextRange.Create(mLine + 1, 0, mLine + 1, 0),
    mIndent + '  ' + AName + ' = ' + AValue + ALineBreak);
end;

type
  /// <summary>Wert einer Property an einem Objekt: gespeichert oder aus der Deklaration.</summary>
  TDfmActual = record
    Stored: Boolean;
    /// <summary>Gespeicherte Property, wenn Stored.</summary>
    Prop: TDfmProperty;
    Value: string;
    /// <summary>Typ der nicht gespeicherten Property; '' wenn unbekannt.</summary>
    TypeName: string;
  end;

  /// <summary>Ein Lauf von dfm-property-check über eine Unit samt Formulardatei.</summary>
  TDfmPropertyRun = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FModel: TFormModel;
    FChecker: TPropertyChecker;
    FUnit: TUnitIndex;
    FClassRange: TTextRange;
    FCanFix: Boolean;
    FLineBreak: string;
    FFormLines: TArray<string>;
    /// <summary>Bereich der Formularklasse; False, wenn die Unit sie nicht deklariert.</summary>
    function FindClassRange: Boolean;
    /// <summary>Wert von ARule.PropertyPath an AObject; False, wenn er unbekannt oder Sache des Vorfahren ist.
    /// </summary>
    function ActualOf(const ARule: TDfmPropertyRule; AObject: TDfmObject; out AActual: TDfmActual): Boolean;
    /// <summary>Gemeldet wird am Feld der Komponente, sonst an der Formularklasse.</summary>
    function RangeOf(AObject: TDfmObject): TTextRange;
    function FixesOf(const ARule: TDfmPropertyRule; AObject: TDfmObject; const AActual: TDfmActual): TArray<TRuleFix>;
    procedure CheckObject(const ARule: TDfmPropertyRule; AObject: TDfmObject);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TDfmPropertyRun }

constructor TDfmPropertyRun.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  // Den Index der Datei teilt der Lauf mit den anderen Regeln.
  FUnit := TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext);
  FModel := TFormModel.Create(AContext.FormText);
  FChecker := TPropertyChecker.Create(AContext, FUnit);
end;

destructor TDfmPropertyRun.Destroy;
begin
  FChecker.Free;
  FModel.Free;
  inherited;
end;

function TDfmPropertyRun.FindClassRange: Boolean;
var
  mSymbol: TIndexSymbol;
begin
  FClassRange := Default(TTextRange);
  for mSymbol in FUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Container = '') and
      SameText(mSymbol.Name, FModel.FormClass) then
    begin
      FClassRange := mSymbol.SelectionRange;
    end;
  end;
  Result := FClassRange.StartPos <> FClassRange.EndPos;
end;

function TDfmPropertyRun.ActualOf(const ARule: TDfmPropertyRule; AObject: TDfmObject;
  out AActual: TDfmActual): Boolean;
var
  mProp: TDfmProperty;
begin
  AActual := Default(TDfmActual);
  for mProp in AObject.Properties do
  begin
    if SameText(mProp.Name, ARule.PropertyPath) then
    begin
      AActual.Stored := True;
      AActual.Prop := mProp;
      AActual.Value := Trim(mProp.Value);
      Exit(True);
    end;
  end;
  // Aus dem Vorfahrenformular und hier nicht gesetzt: Sache des Vorfahren.
  Result := (AObject.Kind <> TDfmObjectKind.Inherited_) and
    FChecker.DefaultValue(AObject.TypeName, ARule.PropertyPath, AActual.Value, AActual.TypeName);
end;

function TDfmPropertyRun.RangeOf(AObject: TDfmObject): TTextRange;
var
  mSymbol: TIndexSymbol;
begin
  Result := FClassRange;
  if AObject = FModel.Document.Root then
  begin
    Exit;
  end;
  for mSymbol in FUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, FModel.FormClass) and
      SameText(mSymbol.Name, AObject.Name) then
    begin
      Exit(mSymbol.SelectionRange);
    end;
  end;
end;

function TDfmPropertyRun.FixesOf(const ARule: TDfmPropertyRule; AObject: TDfmObject;
  const AActual: TDfmActual): TArray<TRuleFix>;
var
  mStringType: Boolean;
  mTarget, mTitle: string;
  mEdit: TRuleEdit;
  mFix: TRuleFix;
begin
  Result := nil;
  if not FCanFix or (ARule.Fix = TDfmFixMode.None) then
  begin
    Exit;
  end;
  if AActual.Stored then
  begin
    mStringType := StartsStr('''', AActual.Value) or StartsStr('#', AActual.Value);
  end
  else
  begin
    mStringType := MatchText(AActual.TypeName, cStringTypes);
  end;
  if not TargetValue(ARule, AActual.Value, mStringType, mTarget, mTitle) then
  begin
    Exit;
  end;
  // Gespeicherten Wert ersetzen oder eine Zeile einfügen.
  if AActual.Stored then
  begin
    mEdit := TRuleEdit.Create(AActual.Prop.ValueRange, mTarget);
  end
  else
  begin
    mEdit := InsertEdit(FFormLines, FLineBreak, AObject, ARule.PropertyPath, mTarget);
  end;
  mFix := TRuleFix.Create(Format('%s: %s', [AObject.Name, mTitle]), [mEdit], ARule.Fix = TDfmFixMode.Auto);
  mFix.FileName := FContext.FormFile;
  Result := [mFix];
end;

procedure TDfmPropertyRun.CheckObject(const ARule: TDfmPropertyRule; AObject: TDfmObject);
var
  mActual: TDfmActual;
  mMessage: string;
begin
  if not FChecker.IsClassOrDescendant(AObject.TypeName, ARule.ClassName, ARule.IncludeDescendants) or
    not ActualOf(ARule, AObject, mActual) or
    TDfmPropertyCheckRule.Satisfies(ARule.Condition, mActual.Value, ARule.Value) then
  begin
    Exit;
  end;
  if ARule.Message <> '' then
  begin
    mMessage := Format('%s (%s): %s', [AObject.Name, AObject.TypeName, ARule.Message]);
  end
  else
  begin
    mMessage := DefaultMessage(ARule, AObject, mActual.Value);
  end;
  FReport.AddWithSeverity(RangeOf(AObject), mMessage, ARule.Severity, FixesOf(ARule, AObject, mActual));
end;

procedure TDfmPropertyRun.Run;
var
  mObjects: TArray<TDfmObject>;
  mObject: TDfmObject;
  mRule: TDfmPropertyRule;
begin
  if (FModel.Document.Root = nil) or (FModel.FormClass = '') or not FindClassRange then
  begin
    Exit;
  end;
  // Korrigiert wird nur eine Text-Formulardatei mit bekanntem Pfad.
  FCanFix := (FContext.FormFile <> '') and not FModel.Binary;
  FLineBreak := TTextLines.LineBreakOf(FContext.FormText);
  FFormLines := nil;
  if FCanFix then
  begin
    FFormLines := FContext.FormText.Replace(#13#10, #10).Split([#10]);
  end;
  mObjects := nil;
  CollectObjects(FModel.Document.Root, mObjects);
  for mRule in FContext.DfmPropertyRules do
  begin
    if (mRule.Severity <> TRuleSeverity.Off) and not IsExcluded(mRule, FContext.RelativePath) then
    begin
      for mObject in mObjects do
      begin
        CheckObject(mRule, mObject);
      end;
    end;
  end;
end;

procedure TDfmPropertyCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mRun: TDfmPropertyRun;
begin
  if (Length(AContext.DfmPropertyRules) = 0) or (AContext.FormText = '') or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  // Gemeldet wird in der Unit: am Feld der Komponente, sonst an der Formularklasse.
  mRun := TDfmPropertyRun.Create(AContext, AReport);
  try
    mRun.Run;
  finally
    mRun.Free;
  end;
end;

class function TDfmPropertyCheckRule.ConfigurationIssues(const ARules: TArray<TDfmPropertyRule>;
  const AIndex: ISymbolIndex; const AReadFile: TRuleFileReader): TArray<TConfigurationIssue>;
var
  mContext: TRuleContext;
  mChecker: TPropertyChecker;
  mRule: TDfmPropertyRule;
  mLocation: TSymbolLocation;
  mMissing: string;
  mIssue: TConfigurationIssue;
begin
  Result := nil;
  if (AIndex = nil) or (Length(ARules) = 0) then
  begin
    Exit;
  end;
  mContext := Default(TRuleContext);
  mContext.Index := AIndex;
  mContext.ReadFile := AReadFile;
  mChecker := TPropertyChecker.Create(mContext, Default(TUnitIndex));
  try
    for mRule in ARules do
    begin
      if mRule.ClassName = '' then
      begin
        Continue;
      end;
      mIssue := Default(TConfigurationIssue);
      if not mChecker.FindClass(mRule.ClassName, mLocation) then
      begin
        mIssue.Range := mRule.ClassRange;
        mIssue.Message := cTexts[TDfmPropertiesText.UnknownClass].Fmt([mRule.ClassName]);
      end
      else if (mRule.PropertyPath <> '') and not mChecker.HasProperty(mRule.ClassName, mRule.PropertyPath,
        mMissing) then
      begin
        mIssue.Range := mRule.PropertyRange;
        mIssue.Message := cTexts[TDfmPropertiesText.NoProperty].Fmt([mRule.ClassName, mMissing]);
      end
      else
      begin
        Continue;
      end;
      Result := Result + [mIssue];
    end;
  finally
    mChecker.Free;
  end;
end;

procedure RegisterDfmPropertyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDfmPropertyCheckRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.DfmProperties', cTexts);

end.
