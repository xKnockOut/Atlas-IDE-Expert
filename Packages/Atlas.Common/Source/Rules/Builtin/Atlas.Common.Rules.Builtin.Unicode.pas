unit Atlas.Common.Rules.Builtin.Unicode;

// Unicode-Sicherheit im Quelltext (#150):
//   bidi-control          bidirektionale Steuerzeichen (Trojan Source, CVE-2021-42574)
//   invisible-char        unsichtbare und Nullbreiten-Zeichen
//   control-char          NUL- und Steuerzeichen, U+FFFD und ungültige UTF-8-Bytes
//   confusable-identifier Bezeichner mit Zeichen, die lateinischen gleichen
//
// Konfidenz nach Ort und Art: Einbettungen und Überschreibungen
// (U+202A–U+202E, U+2066–U+2069) hoch, ausgeglichen in einem String mit
// RTL-Schrift niedrig; Richtungsmarken (U+200E, U+200F, U+061C) niedrig.
// Unsichtbare Zeichen in Strings und Kommentaren mittel, sonst hoch.
// Bezeichner mit Zeichen aus der Confusables-Liste hoch, andere Mischungen
// von Latein mit Griechisch oder Kyrillisch mittel, sonstige Nicht-ASCII-
// Zeichen niedrig.
//
// Aufeinanderfolgende Zeichen derselben Regel ergeben eine Diagnose über
// den ganzen Bereich. Korrekturen: in Strings durch #$XXXX ersetzen (Wert
// bleibt gleich), sonst entfernen; Bezeichner durch lateinische Zeichen.
//
// Text-Formulardateien (FormText) prüfen bidi-control, invisible-char und
// control-char mit: #nnnn-Folgen werden dekodiert; gemeldet wird in der
// Unit am Feld der Komponente bzw. an der Formularklasse, mit Zeile der
// Formulardatei; die Korrektur ändert die Formulardatei.
//
// Ungültige UTF-8-Bytes: control-char liest die Datei über ReadFile und
// meldet die Fehlstellen aus TFileEncoding.InvalidUtf8 mit Zeile und Spalte,
// sofern der gelesene Text dem geprüften entspricht.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TBidiControlRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInvisibleCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TControlCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TConfusableIdentifierRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Lateinisches Gegenstück eines verwechselbaren Zeichens (kyrillisch "а" → "a"); #0 ohne.</summary>
    class function LatinOf(C: Char): Char; static;
  end;

/// <summary>Registriert alle Unicode-Regeln.</summary>
procedure RegisterUnicodeRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Rules.Derived;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wo ein Zeichen steht.</summary>
  TCharPlace = (Code, StringLiteral, Comment);
  /// <summary>Welche Regel ein Zeichen meldet.</summary>
  TCharRule = (Bidi, Invisible, Control);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein auffälliges Zeichen.</summary>
  THit = record
    Code: Integer;
    /// <summary>Offset ab 1 im geprüften Text.</summary>
    Offset: Integer;
    Pos: TTextPosition;
    Confidence: TRuleConfidence;
    /// <summary>Roh im Text; False bei #nnnn in einer Formulardatei.</summary>
    Raw: Boolean;
  end;

  /// <summary>Zusammenhängender Bereich auffälliger Zeichen einer Regel.</summary>
  TRun = record
    Hits: TArray<THit>;
    Place: TCharPlace;
    /// <summary>Hinter dem letzten Zeichen.</summary>
    EndPos: TTextPosition;
    /// <summary>Ende des Bereichs im Text (Offset ab 1, exklusiv).</summary>
    EndOffset: Integer;
    /// <summary>Der umgebende String ist mehrzeilig (''') und lässt sich nicht teilen.</summary>
    MultiLine: Boolean;
  end;

function IsBidiControl(C: Integer): Boolean;
begin
  case C of
    $061C, $200E, $200F, $202A..$202E, $2066..$2069:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Richtungsmarke ohne Einbettung: legitim in RTL-Text.</summary>
function IsBidiMark(C: Integer): Boolean;
begin
  Result := (C = $061C) or (C = $200E) or (C = $200F);
end;

function IsInvisible(C: Integer): Boolean;
begin
  case C of
    $00AD, $180E, $200B..$200D, $2060..$2064, $FEFF:
      Result := True;
  else
    Result := False;
  end;
end;

function IsBadControl(C: Integer): Boolean;
begin
  case C of
    0..8, 11, 14..31, $7F, $FFFD:
      Result := True;
  else
    Result := False;
  end;
end;

function IsRtlLetter(C: Char): Boolean;
begin
  case Ord(C) of
    $0590..$08FF, $FB1D..$FDFF, $FE70..$FEFC:
      Result := True;
  else
    Result := False;
  end;
end;

function Matches(ARule: TCharRule; ACode: Integer): Boolean;
begin
  case ARule of
    TCharRule.Bidi:
      Result := IsBidiControl(ACode);
    TCharRule.Invisible:
      Result := IsInvisible(ACode);
  else
    Result := IsBadControl(ACode);
  end;
end;

function CodeName(ACode: Integer): string;
begin
  Result := 'U+' + IntToHex(ACode, 4);
end;

/// <summary>"U+200B" bzw. "50 Zeichen U+200B, U+200C" für einen Bereich.</summary>
function RunCodes(const ARun: TRun): string;
var
  Codes: TList<Integer>;
  Hit: THit;
  Code: Integer;
begin
  Codes := TList<Integer>.Create;
  try
    for Hit in ARun.Hits do
      if not Codes.Contains(Hit.Code) then
        Codes.Add(Hit.Code);
    Result := '';
    for Code in Codes do
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + CodeName(Code);
    end;
    if Length(ARun.Hits) > 1 then
      Result := Format('%d Zeichen %s', [Length(ARun.Hits), Result]);
  finally
    Codes.Free;
  end;
end;

/// <summary>Ort jedes Zeichens nach den Token des Baums; ohne Baum alles Code.</summary>
function PlacesOf(const AContext: TRuleContext; out AMultiLine: TArray<Boolean>;
  out ATokenStart, ATokenEnd: TArray<Integer>): TArray<TCharPlace>;
var
  Token: TPascalToken;
  Index, Last: Integer;
  Place: TCharPlace;
begin
  SetLength(Result, Length(AContext.Text) + 1);
  SetLength(AMultiLine, Length(AContext.Text) + 1);
  SetLength(ATokenStart, Length(AContext.Text) + 1);
  SetLength(ATokenEnd, Length(AContext.Text) + 1);
  for Index := 0 to High(Result) do
  begin
    Result[Index] := TCharPlace.Code;
    ATokenStart[Index] := Index;
    ATokenEnd[Index] := Index + 1;
  end;
  if AContext.Tree = nil then
    Exit;
  for Token in AContext.Tree.Tokens do
  begin
    case Token.Kind of
      TPascalTokenKind.StringLiteral:
        Place := TCharPlace.StringLiteral;
      TPascalTokenKind.Comment, TPascalTokenKind.Directive:
        Place := TCharPlace.Comment;
    else
      Continue;
    end;
    Last := Token.Offset + Length(Token.Text);
    if Last > Length(AContext.Text) then
      Last := Length(AContext.Text);
    for Index := Token.Offset + 1 to Last do
    begin
      Result[Index] := Place;
      AMultiLine[Index] := StartsStr('''''''', Token.Text);
      ATokenStart[Index] := Token.Offset + 1;
      ATokenEnd[Index] := Last + 1;
    end;
  end;
end;

/// <summary>Stehen alle Einbettungen eines Tokens paarweise geschlossen, und enthält es RTL-Schrift?</summary>
function BalancedRtl(const AText: string; AStart, AStop: Integer): Boolean;
var
  Index, Embeddings, Isolates: Integer;
  Rtl: Boolean;
begin
  Embeddings := 0;
  Isolates := 0;
  Rtl := False;
  for Index := AStart to AStop - 1 do
    case Ord(AText[Index]) of
      $202A, $202B, $202D, $202E:
        Inc(Embeddings);
      $202C:
        begin
          Dec(Embeddings);
          if Embeddings < 0 then
            Exit(False);
        end;
      $2066..$2068:
        Inc(Isolates);
      $2069:
        begin
          Dec(Isolates);
          if Isolates < 0 then
            Exit(False);
        end;
    else
      if IsRtlLetter(AText[Index]) then
        Rtl := True;
    end;
  Result := Rtl and (Embeddings = 0) and (Isolates = 0);
end;

function ConfidenceOf(ARule: TCharRule; ACode: Integer; APlace: TCharPlace; ABalancedRtl: Boolean): TRuleConfidence;
begin
  Result := TRuleConfidence.High;
  case ARule of
    TCharRule.Bidi:
      if IsBidiMark(ACode) or ((APlace = TCharPlace.StringLiteral) and ABalancedRtl) then
        Result := TRuleConfidence.Low;
    TCharRule.Invisible:
      if APlace <> TCharPlace.Code then
        Result := TRuleConfidence.Medium;
  end;
end;

/// <summary>Zusammenhängende Bereiche: gleiche Stelle (Ort), Zeichen direkt hintereinander.</summary>
function RunsOf(ARule: TCharRule; const AContext: TRuleContext): TArray<TRun>;
var
  Places: TArray<TCharPlace>;
  MultiLine: TArray<Boolean>;
  TokenStart, TokenEnd: TArray<Integer>;
  Index, Line, Column: Integer;
  Hit: THit;
  Run: TRun;
  Open: Boolean;
  Code: Integer;

  procedure Flush;
  begin
    if Open then
      Result := Result + [Run];
    Open := False;
  end;

begin
  Result := nil;
  Places := PlacesOf(AContext, MultiLine, TokenStart, TokenEnd);
  Line := 0;
  Column := 0;
  Open := False;
  for Index := 1 to Length(AContext.Text) do
  begin
    Code := Ord(AContext.Text[Index]);
    // BOM am Dateianfang ist erlaubt.
    if Matches(ARule, Code) and not ((Index = 1) and (Code = $FEFF)) then
    begin
      Hit.Code := Code;
      Hit.Offset := Index;
      Hit.Pos := TTextPosition.Create(Line, Column);
      Hit.Raw := True;
      Hit.Confidence := ConfidenceOf(ARule, Code, Places[Index],
        BalancedRtl(AContext.Text, TokenStart[Index], TokenEnd[Index]));
      if Open and ((Run.EndOffset <> Index) or (Run.Place <> Places[Index])) then
        Flush;
      if not Open then
      begin
        Run := Default(TRun);
        Run.Place := Places[Index];
        Run.MultiLine := MultiLine[Index];
        Open := True;
      end;
      Run.Hits := Run.Hits + [Hit];
      Run.EndOffset := Index + 1;
      Run.EndPos := TTextPosition.Create(Line, Column + 1);
    end
    else
      Flush;
    if AContext.Text[Index] = #10 then
    begin
      Inc(Line);
      Column := 0;
    end
    else
      Inc(Column);
  end;
  Flush;
end;

/// <summary>Höchste Konfidenz eines Bereichs: ein gefährliches Zeichen macht den ganzen Bereich gefährlich.</summary>
function RunConfidence(const ARun: TRun): TRuleConfidence;
var
  Hit: THit;
begin
  Result := TRuleConfidence.Low;
  for Hit in ARun.Hits do
    if Ord(Hit.Confidence) > Ord(Result) then
      Result := Hit.Confidence;
end;

/// <summary>"#$200B#$200B" für die Zeichen eines Bereichs.</summary>
function CharLiterals(const ARun: TRun; ADecimal: Boolean): string;
var
  Hit: THit;
begin
  Result := '';
  for Hit in ARun.Hits do
    if ADecimal then
      Result := Result + '#' + IntToStr(Hit.Code)
    else
      Result := Result + '#$' + IntToHex(Hit.Code, 4);
end;

/// <summary>Korrektur eines Bereichs in der geprüften Datei; nil ohne passende.</summary>
function RunFixes(const ARun: TRun): TArray<TRuleFix>;
var
  Range: TTextRange;
begin
  Result := nil;
  Range := TTextRange.Create(ARun.Hits[0].Pos, ARun.EndPos);
  if ARun.Place = TCharPlace.StringLiteral then
  begin
    // 'a<ZWSP>b' → 'a'#$200B'b': gleicher Wert, sichtbar. Mehrzeilige Strings lassen sich nicht teilen.
    if not ARun.MultiLine then
      Result := [TRuleFix.Create('Durch ' + CharLiterals(ARun, False) + ' ersetzen',
        [TRuleEdit.Create(Range, '''' + CharLiterals(ARun, False) + '''')], True)];
  end
  else
    Result := [TRuleFix.Create('Zeichen entfernen', [TRuleEdit.Create(Range, '')])];
end;

function RunRange(const ARun: TRun): TTextRange;
begin
  Result := TTextRange.Create(ARun.Hits[0].Pos, ARun.EndPos);
end;

{ Formulardatei }

type
  /// <summary>Text der Formulardatei mit dem Ort jedes Zeichens; #nnnn-Folgen als eigene Treffer.</summary>
  TFormScan = class
  private
    FText: string;
    FDocument: TDfmDocument;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    /// <summary>Bereiche einer Regel; Place StringLiteral innerhalb von Hochkommas und bei #nnnn.</summary>
    function Runs(ARule: TCharRule): TArray<TRun>;
    /// <summary>Innerstes Objekt und Property an APos; '' ohne.</summary>
    procedure Locate(const APos: TTextPosition; out AObject: TDfmObject; out AProperty: string);
    property Document: TDfmDocument read FDocument;
  end;

constructor TFormScan.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FDocument := TDfmParser.Parse(AText);
end;

destructor TFormScan.Destroy;
begin
  FDocument.Free;
  inherited;
end;

function TFormScan.Runs(ARule: TCharRule): TArray<TRun>;
var
  Index, Line, Column, Start, Code: Integer;
  InQuote, Open: Boolean;
  Run: TRun;
  Hit: THit;
  Digits: string;

  procedure Flush;
  begin
    if Open then
      Result := Result + [Run];
    Open := False;
  end;

  procedure Add(ACode, AOffset, AStop: Integer; APlace: TCharPlace; ARaw: Boolean; AColumnStop: Integer);
  begin
    Hit.Code := ACode;
    Hit.Offset := AOffset;
    Hit.Pos := TTextPosition.Create(Line, Column);
    Hit.Raw := ARaw;
    Hit.Confidence := ConfidenceOf(ARule, ACode, APlace, False);
    if Open and ((Run.EndOffset <> AOffset) or (Run.Place <> APlace)) then
      Flush;
    if not Open then
    begin
      Run := Default(TRun);
      Run.Place := APlace;
      Open := True;
    end;
    Run.Hits := Run.Hits + [Hit];
    Run.EndOffset := AStop;
    Run.EndPos := TTextPosition.Create(Line, AColumnStop);
  end;

begin
  Result := nil;
  Line := 0;
  Column := 0;
  InQuote := False;
  Open := False;
  Index := 1;
  while Index <= Length(FText) do
  begin
    Code := Ord(FText[Index]);
    if FText[Index] = '''' then
    begin
      // '' innerhalb eines Strings ist ein Hochkomma, kein Ende.
      if InQuote and (Index < Length(FText)) and (FText[Index + 1] = '''') then
      begin
        Flush;
        Inc(Index, 2);
        Inc(Column, 2);
        Continue;
      end;
      InQuote := not InQuote;
      Flush;
      Inc(Index);
      Inc(Column);
      Continue;
    end;
    if not InQuote and (FText[Index] = '#') then
    begin
      // Zeichenkonstante #8238 oder #$202E.
      Start := Index;
      Inc(Index);
      if (Index <= Length(FText)) and (FText[Index] = '$') then
      begin
        Inc(Index);
        while (Index <= Length(FText)) and CharInSet(FText[Index], ['0'..'9', 'A'..'F', 'a'..'f']) do
          Inc(Index);
        Digits := '$' + Copy(FText, Start + 2, Index - Start - 2);
      end
      else
      begin
        while (Index <= Length(FText)) and CharInSet(FText[Index], ['0'..'9']) do
          Inc(Index);
        Digits := Copy(FText, Start + 1, Index - Start - 1);
      end;
      // Direkt folgende Konstanten setzen den Bereich fort: #8203#8203 ist eine Folge.
      if TryStrToInt(Digits, Code) and Matches(ARule, Code) then
        Add(Code, Start, Index, TCharPlace.StringLiteral, False, Column + Index - Start)
      else
        Flush;
      Inc(Column, Index - Start);
      Continue;
    end;
    if Matches(ARule, Code) and not ((Index = 1) and (Code = $FEFF)) then
    begin
      if InQuote then
        Add(Code, Index, Index + 1, TCharPlace.StringLiteral, True, Column + 1)
      else
        Add(Code, Index, Index + 1, TCharPlace.Code, True, Column + 1);
    end
    else
      Flush;
    if FText[Index] = #10 then
    begin
      Inc(Line);
      Column := 0;
    end
    else
      Inc(Column);
    Inc(Index);
  end;
  Flush;
end;

function Contains(const ARange: TTextRange; const APos: TTextPosition): Boolean;
begin
  Result := ((APos.Line > ARange.StartPos.Line) or ((APos.Line = ARange.StartPos.Line) and
    (APos.Character >= ARange.StartPos.Character))) and ((APos.Line < ARange.EndPos.Line) or
    ((APos.Line = ARange.EndPos.Line) and (APos.Character <= ARange.EndPos.Character)));
end;

procedure TFormScan.Locate(const APos: TTextPosition; out AObject: TDfmObject; out AProperty: string);

  procedure Visit(AObj: TDfmObject);
  var
    Child: TDfmObject;
    Prop: TDfmProperty;
  begin
    if not Contains(AObj.Range, APos) then
      Exit;
    AObject := AObj;
    AProperty := '';
    for Prop in AObj.Properties do
      if Contains(Prop.ValueRange, APos) or Contains(Prop.NameRange, APos) then
        AProperty := Prop.Name;
    for Child in AObj.Children do
      Visit(Child);
  end;

begin
  AObject := nil;
  AProperty := '';
  if FDocument.Root <> nil then
    Visit(FDocument.Root);
end;

function OnlyReplacement(const ARun: TRun): Boolean;
var
  Hit: THit;
begin
  for Hit in ARun.Hits do
    if Hit.Code <> $FFFD then
      Exit(False);
  Result := True;
end;

/// <summary>Name der Formularklasse in der Unit; Default(TTextRange) ohne.</summary>
function FormClassRange(const AUnitIndex: TUnitIndex; const AFormClass: string): TTextRange;
var
  Symbol: TIndexSymbol;
begin
  Result := Default(TTextRange);
  for Symbol in AUnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and SameText(Symbol.Name, AFormClass) then
      Exit(Symbol.SelectionRange);
end;

/// <summary>Meldet die Bereiche einer Regel in der Formulardatei an der passenden Stelle der Unit.</summary>
procedure CheckForm(ARule: TCharRule; const AContext: TRuleContext; const AReport: IRuleReport;
  const AWhat: string; ASkipReplacement: Boolean);
var
  Scan: TFormScan;
  Run: TRun;
  Obj: TDfmObject;
  PropertyName, Where, FormClass: string;
  Cache: IRuleDerivedCache;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  ClassRange, Range: TTextRange;
  Fixes: TArray<TRuleFix>;
  Fix: TRuleFix;
begin
  if (AContext.FormText = '') or (AContext.Tree = nil) or TFormModel.IsBinary(AContext.FormText) then
    Exit;
  Scan := TFormScan.Create(AContext.FormText);
  try
    if Scan.Document.Root = nil then
      Exit;
    FormClass := Scan.Document.Root.TypeName;
    Cache := TRuleDerived.Open(AContext);
    UnitIndex := TRuleDerived.UnitIndex(Cache, AContext);
    // Ohne Formularklasse in der Unit: am Anfang der Unit.
    ClassRange := FormClassRange(UnitIndex, FormClass);
    for Run in Scan.Runs(ARule) do
    begin
      // U+FFFD an ungültigen Bytes meldet control-char schon mit Zeile und Spalte.
      if ASkipReplacement and OnlyReplacement(Run) then
        Continue;
      Scan.Locate(Run.Hits[0].Pos, Obj, PropertyName);
      Range := ClassRange;
      Where := '';
      if Obj <> nil then
      begin
        Where := Obj.Name;
        if PropertyName <> '' then
          Where := Where + '.' + PropertyName;
        if Obj <> Scan.Document.Root then
          for Symbol in UnitIndex.Symbols do
            if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, FormClass) and
              SameText(Symbol.Name, Obj.Name) then
            begin
              Range := Symbol.SelectionRange;
              Break;
            end;
      end;
      if Where <> '' then
        Where := ' (' + Where + ')';
      Fixes := nil;
      // Rohe Zeichen in einem String der Formulardatei: als #nnnn ausschreiben, wie Delphi es tut.
      if (AContext.FormFile <> '') and (Run.Place = TCharPlace.StringLiteral) and Run.Hits[0].Raw and
        Run.Hits[High(Run.Hits)].Raw then
      begin
        Fix := TRuleFix.Create('In der Formulardatei durch ' + CharLiterals(Run, True) + ' ersetzen',
          [TRuleEdit.Create(RunRange(Run), '''' + CharLiterals(Run, True) + '''')], True);
        Fix.FileName := AContext.FormFile;
        Fixes := [Fix];
      end
      else if (AContext.FormFile <> '') and (Run.Place = TCharPlace.Code) then
      begin
        Fix := TRuleFix.Create('In der Formulardatei entfernen', [TRuleEdit.Create(RunRange(Run), '')]);
        Fix.FileName := AContext.FormFile;
        Fixes := [Fix];
      end;
      AReport.Add(Range, Format('Formulardatei, Zeile %d%s: %s %s', [Run.Hits[0].Pos.Line + 1, Where, AWhat,
        RunCodes(Run)]), RunConfidence(Run), Fixes);
    end;
  finally
    Scan.Free;
  end;
end;

/// <summary>Meldet die Bereiche einer Regel in der Unit und in der Formulardatei.</summary>
procedure CheckText(ARule: TCharRule; const AContext: TRuleContext; const AReport: IRuleReport;
  const AWhat: string);
var
  Run: TRun;
begin
  for Run in RunsOf(ARule, AContext) do
    AReport.Add(RunRange(Run), AWhat + ' ' + RunCodes(Run), RunConfidence(Run), RunFixes(Run));
  CheckForm(ARule, AContext, AReport, AWhat, False);
end;

{ TBidiControlRule }

function TBidiControlRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('bidi-control', TRuleSeverity.Error,
    'Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source)');
end;

procedure TBidiControlRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  CheckText(TCharRule.Bidi, AContext, AReport,
    'Bidirektionales Steuerzeichen, Anzeige und Bedeutung können abweichen (Trojan Source):');
end;

{ TInvisibleCharRule }

function TInvisibleCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('invisible-char', TRuleSeverity.Warning,
    'Unsichtbare oder Nullbreiten-Zeichen im Quelltext');
end;

procedure TInvisibleCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  CheckText(TCharRule.Invisible, AContext, AReport, 'Unsichtbares Zeichen');
end;

{ TControlCharRule }

function TControlCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('control-char', TRuleSeverity.Error,
    'NUL- und Steuerzeichen oder ungültige UTF-8-Bytes im Quelltext und in der Formulardatei');
end;

/// <summary>Text ohne CR, damit Puffer mit anderen Zeilenenden als die Datei vergleichbar bleiben.</summary>
function WithoutCr(const AText: string): string;
begin
  Result := StringReplace(AText, #13, '', [rfReplaceAll]);
end;

/// <summary>Fehlstellen in den Bytes von AFileName, wenn ihr Text AText ist; sonst nil.</summary>
function InvalidBytes(const AContext: TRuleContext; const AFileName, AText: string): TArray<TInvalidUtf8>;
var
  Bytes: TBytes;
  Format: TFileFormat;
begin
  Result := nil;
  if (AFileName = '') or not Assigned(AContext.ReadFile) or
    not AContext.ReadFile(ExtractFileName(StringReplace(AFileName, '/', '\', [rfReplaceAll])), Bytes) then
    Exit;
  if TFileEncoding.IsBinaryForm(Bytes) then
    Exit;
  // Nur, wenn der geprüfte Text der Inhalt der Datei ist: sonst passen die Stellen nicht.
  if WithoutCr(TFileEncoding.Decode(Bytes, Format)) <> WithoutCr(AText) then
    Exit;
  Result := TFileEncoding.InvalidUtf8(Bytes, Format);
end;

/// <summary>Liegen alle Fehlstellen im Text? Sonst zählt der Dekodierer anders als InvalidUtf8, und keine
/// Stelle gilt.</summary>
function Verified(const AInvalid: TArray<TInvalidUtf8>; const AText: string): Boolean;
var
  Lines: TArray<string>;
  Item: TInvalidUtf8;
begin
  Lines := WithoutCr(AText).Split([#10]);
  for Item in AInvalid do
    if (Item.Position.Line > High(Lines)) or (Item.Position.Character >= Length(Lines[Item.Position.Line])) then
      Exit(False);
  Result := True;
end;

/// <summary>Klasse des Wurzelobjekts der Formulardatei; '' ohne.</summary>
function FormClassOf(const AFormText: string): string;
var
  Document: TDfmDocument;
begin
  Result := '';
  Document := TDfmParser.Parse(AFormText);
  try
    if Document.Root <> nil then
      Result := Document.Root.TypeName;
  finally
    Document.Free;
  end;
end;

procedure TControlCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Invalid: TArray<TInvalidUtf8>;
  Item: TInvalidUtf8;
  Run: TRun;
  Hit: THit;
  Covered: Boolean;
  Cache: IRuleDerivedCache;
  Range: TTextRange;
begin
  Invalid := InvalidBytes(AContext, AContext.RelativePath, AContext.Text);
  if not Verified(Invalid, AContext.Text) then
    Invalid := nil;
  for Item in Invalid do
    AReport.Add(TTextRange.Create(Item.Position, TTextPosition.Create(Item.Position.Line,
      Item.Position.Character + 1)), Format('Ungültiges UTF-8-Byte $%s (Byte %d der Datei)',
      [IntToHex(Item.Value, 2), Item.ByteOffset]));
  // U+FFFD an einer schon gemeldeten Fehlstelle nicht doppelt melden.
  for Run in RunsOf(TCharRule.Control, AContext) do
  begin
    Covered := False;
    for Hit in Run.Hits do
      for Item in Invalid do
        if (Hit.Code = $FFFD) and (Item.Position.Line = Hit.Pos.Line) and
          (Item.Position.Character = Hit.Pos.Character) then
          Covered := True;
    if not Covered then
      AReport.Add(RunRange(Run), 'Steuerzeichen oder ungültiges Byte ' + RunCodes(Run), RunConfidence(Run),
        RunFixes(Run));
  end;
  // Ungültige Bytes der Formulardatei: an der Formularklasse, mit Zeile und Spalte der Formulardatei.
  Invalid := nil;
  if (AContext.FormFile <> '') and (AContext.Tree <> nil) and not TFormModel.IsBinary(AContext.FormText) then
    Invalid := InvalidBytes(AContext, AContext.FormFile, AContext.FormText);
  CheckForm(TCharRule.Control, AContext, AReport, 'Steuerzeichen oder ungültiges Byte', Length(Invalid) > 0);
  if Length(Invalid) = 0 then
    Exit;
  Cache := TRuleDerived.Open(AContext);
  Range := FormClassRange(TRuleDerived.UnitIndex(Cache, AContext), FormClassOf(AContext.FormText));
  for Item in Invalid do
    AReport.Add(Range, Format('Formulardatei, Zeile %d, Spalte %d: ungültiges UTF-8-Byte $%s',
      [Item.Position.Line + 1, Item.Position.Character + 1, IntToHex(Item.Value, 2)]));
end;

{ TConfusableIdentifierRule }

type
  TScript = (Other, Latin, Greek, Cyrillic);

function ScriptOf(C: Char): TScript;
begin
  case Ord(C) of
    Ord('A')..Ord('Z'), Ord('a')..Ord('z'), $00C0..$024F:
      Result := TScript.Latin;
    $0370..$03FF:
      Result := TScript.Greek;
    $0400..$04FF, $0500..$052F:
      Result := TScript.Cyrillic;
  else
    Result := TScript.Other;
  end;
end;

class function TConfusableIdentifierRule.LatinOf(C: Char): Char;
begin
  // Auszug aus der Unicode-Confusables-Liste: Zeichen, die lateinischen Buchstaben gleichen.
  case Ord(C) of
    $0430: Result := 'a';
    $0435: Result := 'e';
    $043E: Result := 'o';
    $0440: Result := 'p';
    $0441: Result := 'c';
    $0445: Result := 'x';
    $0443: Result := 'y';
    $0456: Result := 'i';
    $0458: Result := 'j';
    $0455: Result := 's';
    $0501: Result := 'd';
    $04BB: Result := 'h';
    $0410: Result := 'A';
    $0412: Result := 'B';
    $0415: Result := 'E';
    $041A: Result := 'K';
    $041C: Result := 'M';
    $041D: Result := 'H';
    $041E: Result := 'O';
    $0420: Result := 'P';
    $0421: Result := 'C';
    $0422: Result := 'T';
    $0425: Result := 'X';
    $0406: Result := 'I';
    $0408: Result := 'J';
    $0405: Result := 'S';
    $03BF: Result := 'o';
    $03BD: Result := 'v';
    $0391: Result := 'A';
    $0392: Result := 'B';
    $0395: Result := 'E';
    $0396: Result := 'Z';
    $0397: Result := 'H';
    $0399: Result := 'I';
    $039A: Result := 'K';
    $039C: Result := 'M';
    $039D: Result := 'N';
    $039F: Result := 'O';
    $03A1: Result := 'P';
    $03A4: Result := 'T';
    $03A5: Result := 'Y';
    $03A7: Result := 'X';
  else
    Result := #0;
  end;
end;

function TConfusableIdentifierRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('confusable-identifier', TRuleSeverity.Warning,
    'Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen (Verwechslungsgefahr)');
end;

procedure TConfusableIdentifierRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Token: TPascalToken;
  C, Latin: Char;
  Scripts: set of TScript;
  NonAscii, Confusable, OnlyLookalikes: Boolean;
  Range: TTextRange;
  Replaced: string;
  Fixes: TArray<TRuleFix>;
begin
  if AContext.Tree = nil then
    Exit;
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Kind <> TPascalTokenKind.Identifier then
      Continue;
    Scripts := [];
    NonAscii := False;
    Confusable := False;
    OnlyLookalikes := True;
    Replaced := '';
    for C in Token.Text do
    begin
      Latin := C;
      if Ord(C) > 127 then
      begin
        NonAscii := True;
        Latin := LatinOf(C);
        if Latin <> #0 then
          Confusable := True
        else
          OnlyLookalikes := False;
      end;
      if Latin = #0 then
        Replaced := Replaced + C
      else
        Replaced := Replaced + Latin;
      Include(Scripts, ScriptOf(C));
    end;
    if not NonAscii then
      Continue;
    Range := TTextRange.Create(Token.StartPos, Token.EndPos);
    Fixes := nil;
    // Eindeutig nur, wenn jedes Nicht-ASCII-Zeichen ein lateinisches Gegenstück hat.
    if Confusable and OnlyLookalikes then
      Fixes := [TRuleFix.Create(Format('Durch "%s" mit lateinischen Zeichen ersetzen', [Replaced]),
        [TRuleEdit.Create(Range, Replaced)])];
    if Confusable and ((TScript.Latin in Scripts) or OnlyLookalikes) then
      AReport.Add(Range, Format('Bezeichner "%s" enthält Zeichen, die lateinischen gleichen; Verwechslung mit "%s" ' +
        'möglich', [Token.Text, Replaced]), TRuleConfidence.High, Fixes)
    else if (TScript.Latin in Scripts) and ((TScript.Greek in Scripts) or (TScript.Cyrillic in Scripts)) then
      AReport.Add(Range, Format('Bezeichner "%s" mischt Schriften', [Token.Text]), TRuleConfidence.Medium)
    else
      AReport.Add(Range, Format('Bezeichner "%s" enthält Nicht-ASCII-Zeichen', [Token.Text]), TRuleConfidence.Low);
  end;
end;

procedure RegisterUnicodeRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TBidiControlRule.Create);
  ARegistry.Register(TInvisibleCharRule.Create);
  ARegistry.Register(TControlCharRule.Create);
  ARegistry.Register(TConfusableIdentifierRule.Create);
end;

end.
