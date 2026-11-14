unit Atlas.Common.Leaks.Internals.MainScan;

// Hauptquelltext (.dpr) für die Leckprüfung durchsehen (#1880): uses-Einträge
// mit Stelle und ob sie nur in {$IFDEF DEBUG} stehen, Anfang des Hauptblocks,
// Zuweisungen an ReportMemoryLeaksOnShutdown und FastMM_LogToFileEvents.
// Kommentare und Strings zählen nicht. Debug gilt in {$IFDEF DEBUG},
// {$IF DEFINED(DEBUG)} und im {$ELSE} von {$IFNDEF DEBUG}.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  TLeakMainScan = record
  private
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    FText: string;
    // Je offener Bedingung: 1 = Debug, -1 = nicht Debug, 0 = neutral.
    FGuards: TArray<Integer>;
    FDepth: Integer;
    FCandidate: Integer;
    function Guarded: Boolean;
    procedure HandleDirective(const AText: string);
    function Current: TPascalToken;
    function NextSignificant(AFrom: Integer): Integer;
    procedure ReadUses;
    procedure ReadEntry;
    procedure ReadStatementWord;
    procedure Step;
    function StartsLine(const AToken: TPascalToken): Boolean;
  public
    /// <summary>Es gibt ein uses vor dem Hauptblock.</summary>
    UsesFound: Boolean;
    /// <summary>Zahl der Einträge im uses.</summary>
    EntryCount: Integer;
    /// <summary>Stelle des ersten Eintrags (0-basiert).</summary>
    FirstEntry: TTextPosition;
    /// <summary>Vor dem ersten Eintrag stehen in seiner Zeile nur Leerzeichen.</summary>
    FirstEntryStartsLine: Boolean;
    /// <summary>Index des ersten FastMM4/FastMM5 im uses; -1 = keiner.</summary>
    ManagerIndex: Integer;
    /// <summary>1 = FastMM4, 2 = FastMM5 (Ordnungszahl von TLeakManager).</summary>
    ManagerKind: Integer;
    ManagerDebugOnly: Boolean;
    /// <summary>DUnitX.TestFramework im uses.</summary>
    UsesDUnitX: Boolean;
    /// <summary>Erster Leckmonitor von DUnitX im uses; '' = keiner.</summary>
    LeakMonitor: string;
    /// <summary>Zeile (0-basiert) des begin des Hauptblocks; -1 = keiner.</summary>
    MainBegin: Integer;
    /// <summary>Zeile (ab 1) der ersten Zuweisung an ReportMemoryLeaksOnShutdown; 0 = keine.</summary>
    ReportLine: Integer;
    ReportDebugOnly: Boolean;
    /// <summary>Zuweisung an FastMM_LogToFileEvents (Bericht als Datei, FastMM5).</summary>
    LogToFile: Boolean;
    class function Run(const AText: string): TLeakMainScan; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer;

const
  cDebug = 1;
  cNotDebug = -1;
  cNeutral = 0;

/// <summary>Argument einer Direktive in Großbuchstaben ohne Name und Klammern: {$IFDEF Debug} → DEBUG.</summary>
function DirectiveArgument(const AText, AName: string): string;
var
  mStart: Integer;
begin
  mStart := Pos(UpperCase(AName), UpperCase(AText)) + Length(AName);
  Result := Copy(AText, mStart, MaxInt);
  if EndsStr('*)', Result) then
  begin
    SetLength(Result, Length(Result) - 2);
  end
  else if EndsStr('}', Result) then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
  Result := UpperCase(Trim(Result));
end;

/// <summary>Art einer öffnenden Bedingung.</summary>
function GuardOf(const AName, AArgument: string): Integer;
begin
  Result := cNeutral;
  if AName = 'IFDEF' then
  begin
    if AArgument = 'DEBUG' then
    begin
      Result := cDebug;
    end;
  end
  else if AName = 'IFNDEF' then
  begin
    if AArgument = 'DEBUG' then
    begin
      Result := cNotDebug;
    end;
  end
  else if (AName = 'IF') and (StringReplace(AArgument, ' ', '', [rfReplaceAll]) = 'DEFINED(DEBUG)') then
  begin
    Result := cDebug;
  end;
end;

function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(AToken.Text, AWord);
end;

{ TLeakMainScan }

class function TLeakMainScan.Run(const AText: string): TLeakMainScan;
begin
  Result := Default(TLeakMainScan);
  Result.FText := AText;
  Result.FTokens := TPascalLexer.Tokenize(AText);
  Result.ManagerIndex := -1;
  Result.MainBegin := -1;
  Result.FCandidate := -1;
  while Result.FIndex < Length(Result.FTokens) do
  begin
    Result.Step;
  end;
  // Nur der Bericht gehört nach außen.
  Result.FTokens := nil;
  Result.FText := '';
  Result.FGuards := nil;
end;

function TLeakMainScan.Current: TPascalToken;
begin
  Result := FTokens[FIndex];
end;

function TLeakMainScan.Guarded: Boolean;
var
  mGuard: Integer;
begin
  Result := False;
  for mGuard in FGuards do
  begin
    if mGuard = cDebug then
    begin
      Exit(True);
    end;
  end;
end;

procedure TLeakMainScan.HandleDirective(const AText: string);
var
  mName: string;
begin
  mName := TPascalLexer.DirectiveName(AText);
  if (mName = 'IFDEF') or (mName = 'IFNDEF') or (mName = 'IF') or (mName = 'IFOPT') then
  begin
    FGuards := FGuards + [GuardOf(mName, DirectiveArgument(AText, mName))];
  end
  else if (mName = 'ELSE') and (Length(FGuards) > 0) then
  begin
    FGuards[High(FGuards)] := -FGuards[High(FGuards)];
  end
  else if (mName = 'ELSEIF') and (Length(FGuards) > 0) then
  begin
    FGuards[High(FGuards)] := cNeutral;
  end
  else if ((mName = 'ENDIF') or (mName = 'IFEND')) and (Length(FGuards) > 0) then
  begin
    SetLength(FGuards, Length(FGuards) - 1);
  end;
end;

function TLeakMainScan.NextSignificant(AFrom: Integer): Integer;
begin
  Result := AFrom;
  while (Result < Length(FTokens)) and
    (FTokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

function TLeakMainScan.StartsLine(const AToken: TPascalToken): Boolean;
var
  mPos: Integer;
begin
  // Offset ist 0-basiert, der Text 1-basiert: FText[Offset] ist das Zeichen davor.
  mPos := AToken.Offset;
  while (mPos >= 1) and CharInSet(FText[mPos], [' ', #9]) do
  begin
    Dec(mPos);
  end;
  Result := (mPos < 1) or CharInSet(FText[mPos], [#10, #13]);
end;

procedure TLeakMainScan.ReadEntry;
var
  mStart: TPascalToken;
  mName: string;
  mGuarded: Boolean;
begin
  mStart := Current;
  mGuarded := Guarded;
  mName := mStart.Text;
  Inc(FIndex);
  // Punktierte Namen: System.SysUtils
  while (FIndex + 1 < Length(FTokens)) and Current.IsSymbol('.') do
  begin
    mName := mName + '.' + FTokens[FIndex + 1].Text;
    Inc(FIndex, 2);
  end;
  if EntryCount = 0 then
  begin
    FirstEntry := mStart.StartPos;
    FirstEntryStartsLine := StartsLine(mStart);
  end;
  if (ManagerIndex < 0) and (SameText(mName, 'FastMM4') or SameText(mName, 'FastMM5')) then
  begin
    ManagerIndex := EntryCount;
    ManagerKind := 1 + Ord(SameText(mName, 'FastMM5'));
    ManagerDebugOnly := mGuarded;
  end;
  if SameText(mName, 'DUnitX.TestFramework') then
  begin
    UsesDUnitX := True;
  end;
  if (LeakMonitor = '') and StartsText('DUnitX.MemoryLeakMonitor.', mName) then
  begin
    LeakMonitor := mName;
  end;
  Inc(EntryCount);
end;

procedure TLeakMainScan.ReadUses;
begin
  UsesFound := True;
  Inc(FIndex);
  while FIndex < Length(FTokens) do
  begin
    if Current.Kind = TPascalTokenKind.Directive then
    begin
      HandleDirective(Current.Text);
    end
    else if Current.IsSymbol(';') then
    begin
      Inc(FIndex);
      Exit;
    end
    else if (Current.Kind = TPascalTokenKind.Identifier) and not IsWord(Current, 'in') then
    begin
      ReadEntry;
      Continue;
    end;
    Inc(FIndex);
  end;
end;

/// <summary>Blöcke zählen; das begin auf Tiefe 0, dessen end ein Punkt folgt, ist der Hauptblock.</summary>
procedure TLeakMainScan.ReadStatementWord;
var
  mNext: Integer;
begin
  if IsWord(Current, 'begin') or IsWord(Current, 'case') or IsWord(Current, 'try') or IsWord(Current, 'asm') then
  begin
    if (FDepth = 0) and IsWord(Current, 'begin') then
    begin
      FCandidate := Current.StartPos.Line;
    end;
    Inc(FDepth);
  end
  else if IsWord(Current, 'end') and (FDepth > 0) then
  begin
    Dec(FDepth);
    mNext := NextSignificant(FIndex + 1);
    if (FDepth = 0) and (mNext < Length(FTokens)) and FTokens[mNext].IsSymbol('.') then
    begin
      MainBegin := FCandidate;
    end;
  end;
end;

procedure TLeakMainScan.Step;
var
  mNext: Integer;
begin
  case Current.Kind of
    TPascalTokenKind.Directive:
      HandleDirective(Current.Text);
    TPascalTokenKind.Keyword:
      if IsWord(Current, 'uses') and not UsesFound and (FDepth = 0) then
      begin
        ReadUses;
        Exit;
      end
      else
      begin
        ReadStatementWord;
      end;
    TPascalTokenKind.Identifier:
      begin
        mNext := NextSignificant(FIndex + 1);
        if (mNext < Length(FTokens)) and FTokens[mNext].IsSymbol(':=') then
        begin
          if (ReportLine = 0) and SameText(Current.Text, 'ReportMemoryLeaksOnShutdown') then
          begin
            ReportLine := Current.StartPos.Line + 1;
            ReportDebugOnly := Guarded;
          end;
          if SameText(Current.Text, 'FastMM_LogToFileEvents') then
          begin
            LogToFile := True;
          end;
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Inc(FIndex);
end;

end.
