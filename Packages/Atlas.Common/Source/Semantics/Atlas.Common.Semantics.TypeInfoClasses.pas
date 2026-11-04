unit Atlas.Common.Semantics.TypeInfoClasses;

// Standardsichtbarkeit von Klassenmitgliedern ohne Sichtbarkeitsabschnitt
// (#537): published, wenn die Klasse mit RTTI für published übersetzt wird,
// sonst public. Das gilt, wenn bei ihrer Deklaration {$M+} bzw.
// {$TYPEINFO ON} aktiv ist oder ein Vorfahr so übersetzt wurde (TPersistent
// in System.Classes und alles, was davon abstammt).
// - SwitchAt liest den Schalter an einer Stelle aus den aktiven Direktiven:
//   {$M+}, {$M-}, {$TYPEINFO ON|OFF}, auch in Listen wie {$R-,M+} und in
//   (*$ … *); {$M 16384,1048576} (Stapelgröße) zählt nicht. Inaktive Zweige
//   von $IFDEF/$IF bleiben außen vor (Vordefinitionen von Delphi).
//   {$PUSHOPT} sichert den Stand, {$POPOPT} stellt ihn wieder her (#847).
// - HasTypeInfo folgt der Vorfahrenkette über den Symbolindex und liest dazu
//   die Deklaration der Vorfahren aus ihrer Datei. Fehlt ein Vorfahr im Index
//   (RTL und VCL nicht indiziert), entscheiden die bekannten Klassen der RTL,
//   VCL und FMX, die von TPersistent abstammen (KnownTypeInfoClass).
// Ergebnisse bleiben je Instanz gemerkt; eine Instanz je Anfrage.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract;

type
  TTypeInfoReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TTypeInfoClasses = class
  public const
    MaxDepth = 32;
  private
    FIndex: ISymbolIndex;
    FReadText: TTypeInfoReadText;
    FKnown: TDictionary<string, Boolean>;
    function Resolve(const AClassName: string; ADepth: Integer): Boolean;
    /// <summary>{$M+} bei der Deklaration AFound, sonst beim Vorfahren.</summary>
    function ResolveDeclared(const AFound: TSymbolLocation; ADepth: Integer): Boolean;
  public
    /// <summary>AIndex und AReadText dürfen nil sein; dann gelten nur die bekannten Klassen.</summary>
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TTypeInfoReadText);
    destructor Destroy; override;
    /// <summary>Wird AClassName (auch qualifiziert) mit RTTI für published übersetzt?</summary>
    function HasTypeInfo(const AClassName: string): Boolean;
    /// <summary>Klassen der RTL, VCL und FMX, die von TPersistent abstammen, samt TPersistent.</summary>
    class function KnownTypeInfoClass(const AClassName: string): Boolean; static;
    /// <summary>Ist {$M+} an APosition aktiv? ATokens sind die aktiven Token (Direktiven eingeschlossen).</summary>
    class function SwitchAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean;
      overload; static;
    /// <summary>Wie oben; liest die aktiven Token aus AText.</summary>
    class function SwitchAt(const AText: string; const APosition: TTextPosition): Boolean; overload; static;
    /// <summary>Aktive Token von AText: ohne inaktive Zweige von $IFDEF/$IF.</summary>
    class function ActiveTokens(const AText: string): TArray<TPascalToken>; static;
    /// <summary>Wirkung einer Direktive auf den Schalter: True/False in AOn, wenn sie ihn setzt.</summary>
    class function ReadSwitch(const ADirective: string; out AOn: Boolean): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Preprocessor;

const
  Platform_ = 'Win32';
  CompilerVersion_ = 37.0;
  KnownClasses: array[0..39] of string = ('tpersistent', 'tinterfacedpersistent', 'tcomponent', 'tcollection',
    'tcollectionitem', 'townedcollection', 'tstrings', 'tstringlist', 'tbasicaction', 'tcontainedaction',
    'tcustomaction', 'taction', 'tcontrol', 'twincontrol', 'tcustomcontrol', 'tgraphiccontrol', 'tscrollingwincontrol',
    'tcustomform', 'tform', 'tcustomframe', 'tframe', 'tdatamodule', 'tgraphicsobject', 'tfont', 'tbrush', 'tpen',
    'tgraphic', 'tbitmap', 'tpicture', 'tcustomimagelist', 'timagelist', 'tmenuitem', 'tmenu', 'tmainmenu',
    'tpopupmenu', 'tdataset', 'tfield', 'tcommoncustomform', 'tfmxobject', 'tstyledcontrol');

function ShortName(const AName: string): string;
begin
  Result := LowerCase(Copy(AName, LastDelimiter('.', AName) + 1, MaxInt));
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

{ TTypeInfoClasses }

constructor TTypeInfoClasses.Create(const AIndex: ISymbolIndex; const AReadText: TTypeInfoReadText);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FKnown := TDictionary<string, Boolean>.Create;
end;

destructor TTypeInfoClasses.Destroy;
begin
  FKnown.Free;
  inherited Destroy;
end;

class function TTypeInfoClasses.KnownTypeInfoClass(const AClassName: string): Boolean;
var
  Name, Known: string;
begin
  Name := ShortName(AClassName);
  for Known in KnownClasses do
  begin
    if Name = Known then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TTypeInfoClasses.ReadSwitch(const ADirective: string; out AOn: Boolean): Boolean;
var
  Body, Part, Upper: string;
  Found: Boolean;
begin
  AOn := False;
  Body := Trim(ADirective);
  if Body.StartsWith('{$') and Body.EndsWith('}') then
  begin
    Body := Copy(Body, 3, Length(Body) - 3);
  end
  else if Body.StartsWith('(*$') and Body.EndsWith('*)') then
  begin
    Body := Copy(Body, 4, Length(Body) - 5);
  end
  else
  begin
    Exit(False);
  end;
  Upper := UpperCase(Trim(Body));
  if Upper.StartsWith('TYPEINFO') then
  begin
    Upper := Trim(Copy(Upper, 9, MaxInt));
    if Upper = 'ON' then
    begin
      AOn := True;
    end
    else if Upper <> 'OFF' then
    begin
      Exit(False);
    end;
    Exit(True);
  end;
  // Schalterliste: {$M+} oder {$R-,M+,H+}; der letzte M-Schalter gilt.
  Found := False;
  for Part in Upper.Split([',']) do
  begin
    if Trim(Part) = 'M+' then
    begin
      AOn := True;
      Found := True;
    end
    else if Trim(Part) = 'M-' then
    begin
      AOn := False;
      Found := True;
    end;
  end;
  Result := Found;
end;

class function TTypeInfoClasses.SwitchAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Boolean;
var
  Token: TPascalToken;
  Value: Boolean;
  Saved: TArray<Boolean>;
  Name: string;
begin
  Result := False;
  Saved := nil;
  for Token in ATokens do
  begin
    if not Before(Token.StartPos, APosition) then
    begin
      Break;
    end;
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    if ReadSwitch(Token.Text, Value) then
    begin
      Result := Value;
      Continue;
    end;
    // {$PUSHOPT}/{$POPOPT} (#847).
    Name := UpperCase(StringReplace(Token.Text, ' ', '', [rfReplaceAll]));
    if (Name = '{$PUSHOPT}') or (Name = '(*$PUSHOPT*)') then
    begin
      Saved := Saved + [Result];
    end
    else if ((Name = '{$POPOPT}') or (Name = '(*$POPOPT*)')) and (Saved <> nil) then
    begin
      Result := Saved[High(Saved)];
      SetLength(Saved, Length(Saved) - 1);
    end;
  end;
end;

class function TTypeInfoClasses.ActiveTokens(const AText: string): TArray<TPascalToken>;
var
  Options: TPreprocessorOptions;
  Processed: TPreprocessorResult;
  Index: Integer;
begin
  // Ohne bedingte Direktive sind alle Token aktiv.
  if (Pos('{$IF', UpperCase(AText)) = 0) and (Pos('(*$IF', UpperCase(AText)) = 0) then
  begin
    Exit(TPascalLexer.Tokenize(AText));
  end;
  Options := TPreprocessorOptions.Default;
  Options.Defines := TPascalPreprocessor.PredefinedSymbols(Platform_, CompilerVersion_);
  Options.CompilerVersion := CompilerVersion_;
  Options.RTLVersion := CompilerVersion_;
  Processed := TPascalPreprocessor.Process(AText, Options);
  // Nur Token der Datei selbst, nicht aus Include-Dateien.
  Result := nil;
  for Index := 0 to High(Processed.Tokens) do
  begin
    if (Index > High(Processed.FileIndexes)) or (Processed.FileIndexes[Index] = 0) then
    begin
      Result := Result + [Processed.Tokens[Index]];
    end;
  end;
end;

class function TTypeInfoClasses.SwitchAt(const AText: string; const APosition: TTextPosition): Boolean;
begin
  Result := SwitchAt(ActiveTokens(AText), APosition);
end;

/// <summary>Klasse AKey auf oberster Ebene aus AIndex; False ohne.</summary>
function FindClass(const AIndex: ISymbolIndex; const AKey: string; out AFound: TSymbolLocation): Boolean;
var
  mLocation: TSymbolLocation;
begin
  for mLocation in AIndex.FindSymbols(AKey) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') then
    begin
      AFound := mLocation;
      Exit(True);
    end;
  end;
  AFound := Default(TSymbolLocation);
  Result := False;
end;

function TTypeInfoClasses.ResolveDeclared(const AFound: TSymbolLocation; ADepth: Integer): Boolean;
var
  mText, mFileName: string;
begin
  Result := False;
  // Aus einer Include-Datei (#500) deren Datei, sonst die der Unit.
  mFileName := AFound.FileName;
  if AFound.Symbol.FileName <> '' then
  begin
    mFileName := AFound.Symbol.FileName;
  end;
  if Assigned(FReadText) and FReadText(mFileName, mText) then
  begin
    Result := SwitchAt(mText, AFound.Symbol.Range.StartPos);
  end;
  if not Result and (Length(AFound.Symbol.Ancestors) > 0) then
  begin
    Result := Resolve(AFound.Symbol.Ancestors[0], ADepth + 1);
  end;
end;

function TTypeInfoClasses.Resolve(const AClassName: string; ADepth: Integer): Boolean;
var
  mKey: string;
  mFound: TSymbolLocation;
begin
  mKey := ShortName(AClassName);
  if (mKey = '') or (mKey = 'tobject') or (ADepth > MaxDepth) then
  begin
    Exit(False);
  end;
  if FKnown.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  // Gegen Zyklen (A = class(B), B = class(A)): vorläufig nein.
  FKnown.AddOrSetValue(mKey, False);
  Result := KnownTypeInfoClass(mKey);
  if not Result and (FIndex <> nil) and FindClass(FIndex, mKey, mFound) then
  begin
    Result := ResolveDeclared(mFound, ADepth);
  end;
  FKnown.AddOrSetValue(mKey, Result);
end;

function TTypeInfoClasses.HasTypeInfo(const AClassName: string): Boolean;
begin
  Result := Resolve(AClassName, 0);
end;

end.
