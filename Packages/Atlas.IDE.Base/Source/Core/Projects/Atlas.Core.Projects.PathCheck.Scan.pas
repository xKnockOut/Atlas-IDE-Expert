unit Atlas.Core.Projects.PathCheck.Scan;

// Lesen einer Quelltextdatei für „Suchpfade und Defines prüfen“ (#759), ohne
// VCL und Open Tools API: uses (bei Packages auch contains und requires),
// bedingte Symbole, $DEFINE und eingebundene Dateien; bedingte Abschnitte
// werden mit den gegebenen Symbolen ausgewertet. Die Prüfung selbst steht in
// Atlas.Core.Projects.PathCheck, die die Typen unter gleichem Namen weitergibt.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Stand eines Zweigs: gilt, gilt nicht, oder die Bedingung ließ sich nicht auswerten.</summary>
  TAtlasBranchState = (Active, Inactive, Unknown);
{$SCOPEDENUMS OFF}

  TAtlasUsedUnit = record
    /// <summary>Name wie geschrieben, z. B. "System.SysUtils".</summary>
    Name: string;
    /// <summary>Pfad aus "in 'Pfad'"; '' ohne.</summary>
    InFile: string;
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    State: TAtlasBranchState;
  end;

  TAtlasSymbolUse = record
    Name: string;
    Line: Integer;
  end;

  TAtlasSourceScan = record
    /// <summary>Paket (.dpk): contains zählt wie uses.</summary>
    IsPackage: Boolean;
    Units: TArray<TAtlasUsedUnit>;
    /// <summary>Symbole aus $IFDEF, $IFNDEF und DEFINED(…), auch in inaktiven Zweigen.</summary>
    Referenced: TArray<TAtlasSymbolUse>;
    /// <summary>Symbole aus $DEFINE, auch in inaktiven Zweigen (gesetzt in irgendeiner Konfiguration).</summary>
    Defined: TArray<string>;
    /// <summary>Dateinamen aus $I und $INCLUDE, wie geschrieben.</summary>
    Includes: TArray<string>;
    /// <summary>Paket (.dpk): Namen aus requires.</summary>
    Requires: TArray<TAtlasUsedUnit>;
  end;

  TAtlasPathScan = class
  public
    /// <summary>uses, bedingte Symbole und eingebundene Dateien von AText; ADefines gelten zu Beginn.</summary>
    class function Scan(const AText: string; const ADefines: TArray<string>): TAtlasSourceScan; static;
    /// <summary>Wertet einen $IF-Ausdruck aus DEFINED(…), NOT, AND, OR und Klammern aus; alles andere ergibt
    /// Unknown.</summary>
    class function Evaluate(const AExpression: string; const ADefines: TArray<string>): TAtlasBranchState; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.Chars;

{ Bedingungen }

type
  TBranch = record
    State: TAtlasBranchState;
    /// <summary>Ein Zweig galt sicher.</summary>
    Taken: Boolean;
    /// <summary>Ein Zweig war unbekannt: Spätere können nicht mehr sicher gelten.</summary>
    Unsure: Boolean;
    Parent: TAtlasBranchState;
  end;

  TExpressionParser = class
  private
    FTokens: TArray<string>;
    FPos: Integer;
    FDefines: TDictionary<string, Boolean>;
    FFailed: Boolean;
    function Peek: string;
    function Next: string;
    function ParseOr: TAtlasBranchState;
    function ParseAnd: TAtlasBranchState;
    function ParseUnary: TAtlasBranchState;
  public
    constructor Create(const AExpression: string; ADefines: TDictionary<string, Boolean>);
    function Parse: TAtlasBranchState;
  end;

function Tokenize(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if CharInSet(AText[mIndex], [' ', #9, #10, #13]) then
    begin
      Inc(mIndex);
    end
    else if TTextChars.IsIdentStart(AText[mIndex]) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(AText)) and TTextChars.IsIdentChar(AText[mIndex]) do
      begin
        Inc(mIndex);
      end;
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
    end
    else
    begin
      Result := Result + [AText[mIndex]];
      Inc(mIndex);
    end;
  end;
end;

function StateOf(AValue: Boolean): TAtlasBranchState;
begin
  if AValue then
  begin
    Result := TAtlasBranchState.Active;
  end
  else
  begin
    Result := TAtlasBranchState.Inactive;
  end;
end;

constructor TExpressionParser.Create(const AExpression: string; ADefines: TDictionary<string, Boolean>);
begin
  inherited Create;
  FTokens := Tokenize(AExpression);
  FDefines := ADefines;
end;

function TExpressionParser.Peek: string;
begin
  Result := '';
  if FPos <= High(FTokens) then
  begin
    Result := FTokens[FPos];
  end;
end;

function TExpressionParser.Next: string;
begin
  Result := Peek;
  Inc(FPos);
end;

function TExpressionParser.Parse: TAtlasBranchState;
begin
  FPos := 0;
  FFailed := False;
  Result := ParseOr;
  if FFailed or (FPos <= High(FTokens)) then
  begin
    Result := TAtlasBranchState.Unknown;
  end;
end;

function TExpressionParser.ParseOr: TAtlasBranchState;
var
  mRight: TAtlasBranchState;
begin
  Result := ParseAnd;
  while SameText(Peek, 'or') do
  begin
    Next;
    mRight := ParseAnd;
    if (Result = TAtlasBranchState.Active) or (mRight = TAtlasBranchState.Active) then
    begin
      Result := TAtlasBranchState.Active;
    end
    else if (Result = TAtlasBranchState.Unknown) or (mRight = TAtlasBranchState.Unknown) then
    begin
      Result := TAtlasBranchState.Unknown;
    end
    else
    begin
      Result := TAtlasBranchState.Inactive;
    end;
  end;
end;

function TExpressionParser.ParseAnd: TAtlasBranchState;
var
  mRight: TAtlasBranchState;
begin
  Result := ParseUnary;
  while SameText(Peek, 'and') do
  begin
    Next;
    mRight := ParseUnary;
    if (Result = TAtlasBranchState.Inactive) or (mRight = TAtlasBranchState.Inactive) then
    begin
      Result := TAtlasBranchState.Inactive;
    end
    else if (Result = TAtlasBranchState.Unknown) or (mRight = TAtlasBranchState.Unknown) then
    begin
      Result := TAtlasBranchState.Unknown;
    end
    else
    begin
      Result := TAtlasBranchState.Active;
    end;
  end;
end;

function TExpressionParser.ParseUnary: TAtlasBranchState;
var
  mToken, mName: string;
begin
  mToken := Next;
  if SameText(mToken, 'not') then
  begin
    Result := ParseUnary;
    if Result = TAtlasBranchState.Active then
    begin
      Result := TAtlasBranchState.Inactive;
    end
    else if Result = TAtlasBranchState.Inactive then
    begin
      Result := TAtlasBranchState.Active;
    end;
    Exit;
  end;
  if mToken = '(' then
  begin
    Result := ParseOr;
    if Next <> ')' then
    begin
      FFailed := True;
    end;
    Exit;
  end;
  if SameText(mToken, 'defined') and (Peek = '(') then
  begin
    Next;
    mName := Next;
    if (mName = '') or not TTextChars.IsIdentStart(mName[1]) or (Next <> ')') then
    begin
      FFailed := True;
      Exit(TAtlasBranchState.Unknown);
    end;
    Exit(StateOf(FDefines.ContainsKey(UpperCase(mName))));
  end;
  // CompilerVersion, Declared(…), SizeOf, Zahlen, Vergleiche: nicht auswertbar.
  FFailed := True;
  Result := TAtlasBranchState.Unknown;
end;

{ Scanner }

type
{$SCOPEDENUMS ON}
  TUsesState = (None, ExpectName, NamePart, AfterName, ExpectPath);
{$SCOPEDENUMS OFF}

  TScanner = class
  private
    FText: string;
    FPos: Integer;
    FLine: Integer;
    FDefines: TDictionary<string, Boolean>;
    FStack: TList<TBranch>;
    FResult: TAtlasSourceScan;
    FUses: TUsesState;
    FPending: TAtlasUsedUnit;
    FFirstWord: Boolean;
    /// <summary>Liste nach requires: Namen sind Packages, keine Units.</summary>
    FInRequires: Boolean;
    function Current: TAtlasBranchState;
    procedure Push(ACondition: TAtlasBranchState);
    procedure ElseIf(ACondition: TAtlasBranchState);
    procedure Pop;
    procedure IfDef(const ASymbol: string; ADefined: Boolean; ALine: Integer);
    procedure IfExpression(const AExpression: string; AFirst: Boolean; ALine: Integer);
    /// <summary>Bedingter Abschnitt ($IFDEF … $ENDIF); False bei anderen Direktiven.</summary>
    function BranchDirective(const AName, AArgument, ASymbol: string; ALine: Integer): Boolean;
    /// <summary>$DEFINE, $UNDEF, $I und $INCLUDE.</summary>
    procedure OtherDirective(const AName, AArgument, ASymbol: string);
    procedure Directive(const AText: string; ALine: Integer);
    procedure Reference(const AName: string; ALine: Integer);
    procedure ReferenceAll(const AExpression: string; ALine: Integer);
    procedure Word(const AWord: string; ALine: Integer);
    procedure Symbol(AChar: Char);
    procedure StringLiteral(const AValue: string);
    procedure Commit;
    procedure CountLines(AFrom, ATo: Integer);
    function StartsAt(const AText: string): Boolean;
    procedure SkipLineComment;
    /// <summary>Kommentar von AOpen bis AClose ab FPos; mit „$“ dahinter eine Direktive.</summary>
    procedure Comment(const AOpen, AClose: string);
    /// <summary>Mehrzeiliger String ab FPos überlesen; False, wenn dort keiner beginnt.</summary>
    function MultilineString: Boolean;
    procedure QuotedString;
    procedure ReadWord;
  public
    constructor Create(const AText: string; const ADefines: TArray<string>);
    destructor Destroy; override;
    function Run: TAtlasSourceScan;
  end;

constructor TScanner.Create(const AText: string; const ADefines: TArray<string>);
var
  mName: string;
begin
  inherited Create;
  FText := AText;
  FDefines := TDictionary<string, Boolean>.Create;
  for mName in ADefines do
  begin
    if Trim(mName) <> '' then
    begin
      FDefines.AddOrSetValue(UpperCase(Trim(mName)), True);
    end;
  end;
  FStack := TList<TBranch>.Create;
  FFirstWord := True;
end;

destructor TScanner.Destroy;
begin
  FStack.Free;
  FDefines.Free;
  inherited;
end;

function TScanner.Current: TAtlasBranchState;
begin
  if FStack.Count = 0 then
  begin
    Result := TAtlasBranchState.Active;
  end
  else
  begin
    Result := FStack.Last.State;
  end;
end;

procedure TScanner.Push(ACondition: TAtlasBranchState);
var
  mBranch: TBranch;
begin
  mBranch := Default(TBranch);
  mBranch.Parent := Current;
  case mBranch.Parent of
    TAtlasBranchState.Inactive:
      begin
        mBranch.State := TAtlasBranchState.Inactive;
        // Kein Zweig darunter kann gelten.
        mBranch.Taken := True;
      end;
    TAtlasBranchState.Unknown:
      begin
        if ACondition = TAtlasBranchState.Inactive then
        begin
          mBranch.State := TAtlasBranchState.Inactive;
        end
        else
        begin
          mBranch.State := TAtlasBranchState.Unknown;
        end;
        mBranch.Taken := ACondition = TAtlasBranchState.Active;
        mBranch.Unsure := ACondition = TAtlasBranchState.Unknown;
      end;
  else
    mBranch.State := ACondition;
    mBranch.Taken := ACondition = TAtlasBranchState.Active;
    mBranch.Unsure := ACondition = TAtlasBranchState.Unknown;
  end;
  FStack.Add(mBranch);
end;

procedure TScanner.ElseIf(ACondition: TAtlasBranchState);
var
  mBranch: TBranch;
begin
  if FStack.Count = 0 then
  begin
    Exit;
  end;
  mBranch := FStack.Last;
  if mBranch.Taken or (mBranch.Parent = TAtlasBranchState.Inactive) then
  begin
    mBranch.State := TAtlasBranchState.Inactive;
  end
  else if ACondition = TAtlasBranchState.Inactive then
  begin
    mBranch.State := TAtlasBranchState.Inactive;
  end
  else
  begin
    if mBranch.Unsure or (mBranch.Parent = TAtlasBranchState.Unknown) or
      (ACondition = TAtlasBranchState.Unknown) then
    begin
      mBranch.State := TAtlasBranchState.Unknown;
    end
    else
    begin
      mBranch.State := TAtlasBranchState.Active;
    end;
    // Gilt die Bedingung sicher, kann kein späterer Zweig mehr gelten: Entweder galt ein früherer oder dieser.
    mBranch.Taken := ACondition = TAtlasBranchState.Active;
    mBranch.Unsure := mBranch.Unsure or (ACondition = TAtlasBranchState.Unknown);
  end;
  FStack[FStack.Count - 1] := mBranch;
end;

procedure TScanner.Pop;
begin
  if FStack.Count > 0 then
  begin
    FStack.Delete(FStack.Count - 1);
  end;
end;

procedure TScanner.Reference(const AName: string; ALine: Integer);
var
  mUse: TAtlasSymbolUse;
begin
  if (AName = '') or not TTextChars.IsIdentStart(AName[1]) then
  begin
    Exit;
  end;
  mUse.Name := AName;
  mUse.Line := ALine;
  FResult.Referenced := FResult.Referenced + [mUse];
end;

procedure TScanner.ReferenceAll(const AExpression: string; ALine: Integer);
var
  mTokens: TArray<string>;
  mIndex: Integer;
begin
  mTokens := Tokenize(AExpression);
  for mIndex := 0 to High(mTokens) - 3 do
  begin
    if SameText(mTokens[mIndex], 'defined') and (mTokens[mIndex + 1] = '(') and (mTokens[mIndex + 3] = ')') then
    begin
      Reference(mTokens[mIndex + 2], ALine);
    end;
  end;
end;

function FirstWord(const AText: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(AText)) and TTextChars.IsIdentChar(AText[mIndex]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(AText, 1, mIndex - 1);
end;

function Unquote(const AText: string): string;
begin
  Result := Trim(AText);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

procedure TScanner.IfDef(const ASymbol: string; ADefined: Boolean; ALine: Integer);
var
  mCondition: TAtlasBranchState;
begin
  Reference(ASymbol, ALine);
  mCondition := StateOf(FDefines.ContainsKey(UpperCase(ASymbol)) = ADefined);
  if ASymbol = '' then
  begin
    mCondition := TAtlasBranchState.Unknown;
  end;
  Push(mCondition);
end;

procedure TScanner.IfExpression(const AExpression: string; AFirst: Boolean; ALine: Integer);
var
  mParser: TExpressionParser;
  mCondition: TAtlasBranchState;
begin
  ReferenceAll(AExpression, ALine);
  mParser := TExpressionParser.Create(AExpression, FDefines);
  try
    mCondition := mParser.Parse;
  finally
    mParser.Free;
  end;
  if AFirst then
  begin
    Push(mCondition);
  end
  else
  begin
    ElseIf(mCondition);
  end;
end;

function TScanner.BranchDirective(const AName, AArgument, ASymbol: string; ALine: Integer): Boolean;
begin
  Result := True;
  if (AName = 'IFDEF') or (AName = 'IFNDEF') then
  begin
    IfDef(ASymbol, AName = 'IFDEF', ALine);
  end
  else if (AName = 'IF') or (AName = 'ELSEIF') then
  begin
    IfExpression(AArgument, AName = 'IF', ALine);
  end
  else if AName = 'IFOPT' then
  begin
    Push(TAtlasBranchState.Unknown);
  end
  else if AName = 'ELSE' then
  begin
    ElseIf(TAtlasBranchState.Active);
  end
  else if (AName = 'ENDIF') or (AName = 'IFEND') then
  begin
    Pop;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TScanner.OtherDirective(const AName, AArgument, ASymbol: string);
begin
  if (AName = 'DEFINE') and (ASymbol <> '') then
  begin
    FResult.Defined := FResult.Defined + [ASymbol];
    if Current = TAtlasBranchState.Active then
    begin
      FDefines.AddOrSetValue(UpperCase(ASymbol), True);
    end;
  end
  else if (AName = 'UNDEF') and (ASymbol <> '') then
  begin
    if Current = TAtlasBranchState.Active then
    begin
      FDefines.Remove(UpperCase(ASymbol));
    end;
  end
  else if ((AName = 'I') or (AName = 'INCLUDE')) and (AArgument <> '') and
    not CharInSet(AArgument[1], ['+', '-']) then
  begin
    FResult.Includes := FResult.Includes + [Unquote(AArgument)];
  end;
end;

procedure TScanner.Directive(const AText: string; ALine: Integer);
var
  mName, mArgument: string;
begin
  mName := UpperCase(FirstWord(AText));
  mArgument := Trim(Copy(AText, Length(mName) + 1, MaxInt));
  if not BranchDirective(mName, mArgument, FirstWord(mArgument), ALine) then
  begin
    OtherDirective(mName, mArgument, FirstWord(mArgument));
  end;
end;

procedure TScanner.Commit;
begin
  if (FPending.Name <> '') and FInRequires then
  begin
    FResult.Requires := FResult.Requires + [FPending];
  end
  else if FPending.Name <> '' then
  begin
    FResult.Units := FResult.Units + [FPending];
  end;
  FPending := Default(TAtlasUsedUnit);
end;

procedure TScanner.Word(const AWord: string; ALine: Integer);
begin
  if FFirstWord then
  begin
    FFirstWord := False;
    FResult.IsPackage := SameText(AWord, 'package');
  end;
  case FUses of
    TUsesState.None:
      if SameText(AWord, 'uses') or (FResult.IsPackage and (SameText(AWord, 'contains') or
        SameText(AWord, 'requires'))) then
      begin
        FInRequires := SameText(AWord, 'requires');
        FUses := TUsesState.ExpectName;
        FPending := Default(TAtlasUsedUnit);
      end;
    TUsesState.ExpectName:
      begin
        FPending := Default(TAtlasUsedUnit);
        FPending.Name := AWord;
        FPending.Line := ALine;
        FPending.State := Current;
        FUses := TUsesState.AfterName;
      end;
    TUsesState.NamePart:
      begin
        FPending.Name := FPending.Name + '.' + AWord;
        FUses := TUsesState.AfterName;
      end;
    TUsesState.AfterName:
      if SameText(AWord, 'in') then
      begin
        FUses := TUsesState.ExpectPath;
      end
      else
      begin
        FUses := TUsesState.None;
      end;
  else
    FUses := TUsesState.None;
  end;
end;

procedure TScanner.Symbol(AChar: Char);
begin
  case FUses of
    TUsesState.None:
      Exit;
    TUsesState.AfterName:
      if AChar = '.' then
      begin
        FUses := TUsesState.NamePart;
        Exit;
      end;
    TUsesState.ExpectName: ;
    TUsesState.NamePart: ;
    TUsesState.ExpectPath: ;
  end;
  if AChar = ',' then
  begin
    Commit;
    FUses := TUsesState.ExpectName;
  end
  else if AChar = ';' then
  begin
    Commit;
    FUses := TUsesState.None;
  end
  else
  begin
    FPending := Default(TAtlasUsedUnit);
    FUses := TUsesState.None;
  end;
end;

procedure TScanner.StringLiteral(const AValue: string);
begin
  if FUses = TUsesState.ExpectPath then
  begin
    FPending.InFile := AValue;
    FUses := TUsesState.AfterName;
  end
  else if FUses <> TUsesState.None then
  begin
    FPending := Default(TAtlasUsedUnit);
    FUses := TUsesState.None;
  end;
end;

procedure TScanner.CountLines(AFrom, ATo: Integer);
var
  mIndex: Integer;
begin
  for mIndex := AFrom to ATo do
  begin
    if (mIndex >= 1) and (mIndex <= Length(FText)) and (FText[mIndex] = #10) then
    begin
      Inc(FLine);
    end;
  end;
end;

function TScanner.StartsAt(const AText: string): Boolean;
begin
  Result := Copy(FText, FPos, Length(AText)) = AText;
end;

procedure TScanner.SkipLineComment;
begin
  while (FPos <= Length(FText)) and (FText[FPos] <> #10) do
  begin
    Inc(FPos);
  end;
end;

procedure TScanner.Comment(const AOpen, AClose: string);
var
  mClose, mInner, mStartLine: Integer;
begin
  mInner := FPos + Length(AOpen);
  mClose := Pos(AClose, FText, mInner);
  if mClose = 0 then
  begin
    mClose := Length(FText) + 1;
  end;
  mStartLine := FLine;
  if (mInner <= Length(FText)) and (FText[mInner] = '$') then
  begin
    Directive(Copy(FText, mInner + 1, mClose - mInner - 1), mStartLine);
  end;
  CountLines(FPos, mClose);
  FPos := mClose + Length(AClose);
end;

function TScanner.MultilineString: Boolean;
var
  mClose: Integer;
begin
  // Mehrzeiliger String (Delphi 12): ''' am Zeilenende bis zum nächsten '''.
  Result := StartsAt('''''''') and (FPos + 3 <= Length(FText)) and CharInSet(FText[FPos + 3], [#10, #13]);
  if not Result then
  begin
    Exit;
  end;
  mClose := Pos('''''''', FText, FPos + 3);
  if mClose = 0 then
  begin
    mClose := Length(FText) + 1;
  end;
  CountLines(FPos, mClose);
  FPos := mClose + 3;
  StringLiteral('');
end;

procedure TScanner.QuotedString;
var
  mValue: string;
begin
  if MultilineString then
  begin
    Exit;
  end;
  mValue := '';
  Inc(FPos);
  while (FPos <= Length(FText)) and (FText[FPos] <> #10) do
  begin
    if StartsAt('''''') then
    begin
      mValue := mValue + '''';
      Inc(FPos, 2);
    end
    else if FText[FPos] = '''' then
    begin
      Break;
    end
    else
    begin
      mValue := mValue + FText[FPos];
      Inc(FPos);
    end;
  end;
  // Schließendes Hochkomma überspringen; ein Zeilenende bleibt für die Zeilenzählung stehen.
  if (FPos <= Length(FText)) and (FText[FPos] = '''') then
  begin
    Inc(FPos);
  end;
  StringLiteral(mValue);
end;

procedure TScanner.ReadWord;
var
  mStart: Integer;
begin
  if FText[FPos] = '&' then
  begin
    Inc(FPos);
  end;
  mStart := FPos;
  while (FPos <= Length(FText)) and TTextChars.IsIdentChar(FText[FPos]) do
  begin
    Inc(FPos);
  end;
  if FPos > mStart then
  begin
    Word(Copy(FText, mStart, FPos - mStart), FLine);
  end;
end;

function TScanner.Run: TAtlasSourceScan;
var
  C: Char;
begin
  FResult := Default(TAtlasSourceScan);
  FPos := 1;
  FLine := 1;
  while FPos <= Length(FText) do
  begin
    C := FText[FPos];
    if C = #10 then
    begin
      Inc(FLine);
      Inc(FPos);
    end
    else if CharInSet(C, [' ', #9, #13]) then
    begin
      Inc(FPos);
    end
    else if StartsAt('//') then
    begin
      SkipLineComment;
    end
    else if C = '{' then
    begin
      Comment('{', '}');
    end
    else if StartsAt('(*') then
    begin
      Comment('(*', '*)');
    end
    else if C = '''' then
    begin
      QuotedString;
    end
    else if TTextChars.IsIdentStart(C) or (C = '&') then
    begin
      ReadWord;
    end
    else
    begin
      Symbol(C);
      Inc(FPos);
    end;
  end;
  Result := FResult;
end;

{ TAtlasPathScan }

class function TAtlasPathScan.Scan(const AText: string; const ADefines: TArray<string>): TAtlasSourceScan;
var
  mScanner: TScanner;
begin
  mScanner := TScanner.Create(AText, ADefines);
  try
    Result := mScanner.Run;
  finally
    mScanner.Free;
  end;
end;

class function TAtlasPathScan.Evaluate(const AExpression: string;
  const ADefines: TArray<string>): TAtlasBranchState;
var
  mDefines: TDictionary<string, Boolean>;
  mName: string;
  mParser: TExpressionParser;
begin
  mDefines := TDictionary<string, Boolean>.Create;
  try
    for mName in ADefines do
    begin
      mDefines.AddOrSetValue(UpperCase(Trim(mName)), True);
    end;
    mParser := TExpressionParser.Create(AExpression, mDefines);
    try
      Result := mParser.Parse;
    finally
      mParser.Free;
    end;
  finally
    mDefines.Free;
  end;
end;

end.
