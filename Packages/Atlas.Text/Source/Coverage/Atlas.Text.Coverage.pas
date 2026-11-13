unit Atlas.Text.Coverage;

// Liest Berichte der Testabdeckung (#275) von DelphiCodeCoverage, gemeinsam
// für Server und Plugin:
//   - CodeCoverage_Summary.xml mit -xmllines:
//     <report><data><linehits><file name="X.pas">10=1;11=0</file></linehits>
//     Je Zeile mit Code die Zahl der Durchläufe.
//   - jacoco.xml (-jacoco, erst nach Fassung 1.0.15): <sourcefile name="X.pas"><line nr="10" mi="0"
//     ci="1"/>. Nur „durchlaufen“ oder „nicht durchlaufen“; als Zahl 1 bzw. 0.
// Steht eine Datei mehrfach im Bericht (mehrere Module, Generics), werden die
// Durchläufe je Zeile zusammengezählt. Zeilen zählen ab 1 wie im Bericht.

interface

{$SCOPEDENUMS ON}

type
  TCoverageFormat = (None, DelphiCodeCoverage, JaCoCo);
  /// <summary>Warum ein Bericht nicht taugt: kein Abdeckungsbericht, oder ein Bericht von DelphiCodeCoverage
  /// ohne Zeilen (ohne -xmllines erzeugt).</summary>
  TCoverageProblem = (None, NotAReport, NoLines);

  TCoverageLine = record
    /// <summary>Zeile ab 1.</summary>
    Line: Integer;
    /// <summary>Durchläufe; 0 = nicht durchlaufen.</summary>
    Hits: Integer;
  end;

  TCoverageFile = record
    /// <summary>Name wie im Bericht, meist ohne Ordner.</summary>
    Name: string;
    /// <summary>Zeilen mit Code, aufsteigend, jede einmal.</summary>
    Lines: TArray<TCoverageLine>;
    function LineCount: Integer;
    function CoveredCount: Integer;
    /// <summary>Durchläufe in ALine (ab 1); -1, wenn die Zeile keinen Code hat.</summary>
    function HitsAt(ALine: Integer): Integer;
  end;

  TCoverageReport = record
    Format: TCoverageFormat;
    Problem: TCoverageProblem;
    Files: TArray<TCoverageFile>;
    function Valid: Boolean;
    /// <summary>Datei zu APath: gleicher Pfad, Pfad endet auf den Namen im Bericht (der längste gewinnt), sonst
    /// der einzige Eintrag mit demselben Dateinamen; -1 ohne Treffer. Groß-/Kleinschreibung und / bzw. \ egal.
    /// </summary>
    function IndexOf(const APath: string): Integer;
  end;

  TCoverage = record
  public
    class function Parse(const AXml: string): TCoverageReport; static;
    /// <summary>Zeilen aus "10=1;11=0" (Inhalt von linehits/file), aufsteigend, doppelte zusammengezählt;
    /// Kaputtes wird übersprungen.</summary>
    class function ParseLineHits(const AText: string): TArray<TCoverageLine>; static;
    /// <summary>ALines aufsteigend, gleiche Zeilen zusammengezählt.</summary>
    class function Normalized(const ALines: TArray<TCoverageLine>): TArray<TCoverageLine>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Xml;

type
  TCoverageReader = class
  private
    FCursor: TXmlCursor;
    FResult: TCoverageReport;
    FRootSeen: Boolean;
    FIsReport: Boolean;
    FDccSeen: Boolean;
    FInLineHits: Boolean;
    FInHitFile: Boolean;
    FHitFile: string;
    /// <summary>Text der laufenden linehits-Datei; Textknoten können geteilt sein (CDATA).</summary>
    FHitText: TStringBuilder;
    FSourceFile: string;
    FSourceLines: TArray<TCoverageLine>;
    FJacocoFiles: TArray<TCoverageFile>;
    procedure AddFile(var AFiles: TArray<TCoverageFile>; const AName: string;
      const ALines: TArray<TCoverageLine>);
    procedure OpenElement(const AName: string);
    procedure CloseElement(const AName: string);
    procedure ReadLine;
  public
    constructor Create;
    destructor Destroy; override;
    function Read(const AXml: string): TCoverageReport;
  end;

function SlashPath(const APath: string): string;
begin
  Result := LowerCase(Trim(APath).Replace('\', '/'));
end;

function BareName(const APath: string): string;
var
  mSlash: Integer;
begin
  Result := SlashPath(APath);
  mSlash := Result.LastIndexOf('/');
  if mSlash >= 0 then
  begin
    Result := Result.Substring(mSlash + 1);
  end;
end;

{ TCoverageFile }

function TCoverageFile.LineCount: Integer;
begin
  Result := Length(Lines);
end;

function TCoverageFile.CoveredCount: Integer;
var
  mLine: TCoverageLine;
begin
  Result := 0;
  for mLine in Lines do
  begin
    if mLine.Hits > 0 then
    begin
      Inc(Result);
    end;
  end;
end;

function TCoverageFile.HitsAt(ALine: Integer): Integer;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := High(Lines);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if Lines[mMiddle].Line = ALine then
    begin
      Exit(Lines[mMiddle].Hits);
    end;
    if Lines[mMiddle].Line < ALine then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle - 1;
    end;
  end;
  Result := -1;
end;

{ TCoverageReport }

function TCoverageReport.Valid: Boolean;
begin
  Result := Problem = TCoverageProblem.None;
end;

function TCoverageReport.IndexOf(const APath: string): Integer;
var
  mPath, mName, mBare: string;
  mIndex, mBestLength, mBareIndex, mBareCount: Integer;
begin
  mPath := SlashPath(APath);
  mBare := BareName(APath);
  Result := -1;
  mBestLength := 0;
  mBareIndex := -1;
  mBareCount := 0;
  for mIndex := 0 to High(Files) do
  begin
    mName := SlashPath(Files[mIndex].Name);
    if mName = '' then
    begin
      Continue;
    end;
    if mName = mPath then
    begin
      Exit(mIndex);
    end;
    if mPath.EndsWith('/' + mName) and (Length(mName) > mBestLength) then
    begin
      Result := mIndex;
      mBestLength := Length(mName);
    end;
    if BareName(mName) = mBare then
    begin
      mBareIndex := mIndex;
      Inc(mBareCount);
    end;
  end;
  if (Result < 0) and (mBareCount = 1) then
  begin
    Result := mBareIndex;
  end;
end;

{ TCoverage }

class function TCoverage.Normalized(const ALines: TArray<TCoverageLine>): TArray<TCoverageLine>;
var
  mSorted: TArray<TCoverageLine>;
  mLine: TCoverageLine;
  mCount: Integer;
begin
  mSorted := Copy(ALines);
  TArray.Sort<TCoverageLine>(mSorted, TComparer<TCoverageLine>.Construct(
    function(const ALeft, ARight: TCoverageLine): Integer
    begin
      Result := ALeft.Line - ARight.Line;
      if Result = 0 then
      begin
        Result := ALeft.Hits - ARight.Hits;
      end;
    end));
  SetLength(Result, Length(mSorted));
  mCount := 0;
  for mLine in mSorted do
  begin
    if (mCount > 0) and (Result[mCount - 1].Line = mLine.Line) then
    begin
      Result[mCount - 1].Hits := Result[mCount - 1].Hits + mLine.Hits;
    end
    else
    begin
      Result[mCount] := mLine;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TCoverage.ParseLineHits(const AText: string): TArray<TCoverageLine>;
const
  // Platz für so viele Zeilen mehr, wenn das Feld voll ist.
  cLinesGrowth = 16;
var
  mPart: string;
  mEqual, mCount: Integer;
  mLine: TCoverageLine;
begin
  SetLength(Result, 0);
  mCount := 0;
  for mPart in AText.Split([';']) do
  begin
    mEqual := Pos('=', mPart);
    if (mEqual > 0) and TryStrToInt(Trim(Copy(mPart, 1, mEqual - 1)), mLine.Line) and
      TryStrToInt(Trim(Copy(mPart, mEqual + 1, MaxInt)), mLine.Hits) and (mLine.Line > 0) and (mLine.Hits >= 0) then
    begin
      if mCount = Length(Result) then
      begin
        SetLength(Result, mCount * 2 + cLinesGrowth);
      end;
      Result[mCount] := mLine;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
  Result := Normalized(Result);
end;

class function TCoverage.Parse(const AXml: string): TCoverageReport;
var
  mReader: TCoverageReader;
begin
  mReader := TCoverageReader.Create;
  try
    Result := mReader.Read(AXml);
  finally
    mReader.Free;
  end;
end;

{ TCoverageReader }

procedure TCoverageReader.AddFile(var AFiles: TArray<TCoverageFile>; const AName: string;
  const ALines: TArray<TCoverageLine>);
var
  mIndex: Integer;
  mFile: TCoverageFile;
begin
  for mIndex := 0 to High(AFiles) do
  begin
    if SameText(SlashPath(AFiles[mIndex].Name), SlashPath(AName)) then
    begin
      AFiles[mIndex].Lines := TCoverage.Normalized(AFiles[mIndex].Lines + ALines);
      Exit;
    end;
  end;
  mFile.Name := AName;
  mFile.Lines := TCoverage.Normalized(ALines);
  SetLength(AFiles, Length(AFiles) + 1);
  AFiles[High(AFiles)] := mFile;
end;

procedure TCoverageReader.ReadLine;
var
  mLine: TCoverageLine;
  mCovered, mMissed: Integer;
begin
  if not TryStrToInt(FCursor.Attribute('nr'), mLine.Line) or (mLine.Line <= 0) then
  begin
    Exit;
  end;
  mCovered := StrToIntDef(FCursor.Attribute('ci'), 0);
  mMissed := StrToIntDef(FCursor.Attribute('mi'), 0);
  if (mCovered <= 0) and (mMissed <= 0) then
  begin
    Exit;
  end;
  mLine.Hits := 0;
  if mCovered > 0 then
  begin
    mLine.Hits := 1;
  end;
  SetLength(FSourceLines, Length(FSourceLines) + 1);
  FSourceLines[High(FSourceLines)] := mLine;
end;

procedure TCoverageReader.OpenElement(const AName: string);
begin
  if not FRootSeen then
  begin
    FRootSeen := True;
    FIsReport := AName = 'report';
    Exit;
  end;
  if not FIsReport then
  begin
    Exit;
  end;
  if (AName = 'data') or (AName = 'stats') then
  begin
    FDccSeen := True;
  end
  else if AName = 'linehits' then
  begin
    FInLineHits := not FCursor.SelfClosing;
  end
  else if FInLineHits and (AName = 'file') then
  begin
    FHitFile := FCursor.Attribute('name');
    FHitText.Clear;
    FInHitFile := True;
    if FCursor.SelfClosing then
    begin
      CloseElement('file');
    end;
  end
  else if AName = 'sourcefile' then
  begin
    FSourceFile := FCursor.Attribute('name');
    FSourceLines := nil;
    if FCursor.SelfClosing then
    begin
      CloseElement('sourcefile');
    end;
  end
  else if (AName = 'line') and (FSourceFile <> '') then
  begin
    ReadLine;
  end;
end;

procedure TCoverageReader.CloseElement(const AName: string);
begin
  if AName = 'linehits' then
  begin
    FInLineHits := False;
    if FResult.Format = TCoverageFormat.None then
    begin
      FResult.Format := TCoverageFormat.DelphiCodeCoverage;
    end;
  end
  else if FInHitFile and (AName = 'file') then
  begin
    FInHitFile := False;
    FResult.Format := TCoverageFormat.DelphiCodeCoverage;
    AddFile(FResult.Files, FHitFile, TCoverage.ParseLineHits(FHitText.ToString));
  end
  else if (AName = 'sourcefile') and (FSourceFile <> '') then
  begin
    AddFile(FJacocoFiles, FSourceFile, FSourceLines);
    FSourceFile := '';
    FSourceLines := nil;
  end;
end;

constructor TCoverageReader.Create;
begin
  inherited Create;
  FHitText := TStringBuilder.Create;
end;

destructor TCoverageReader.Destroy;
begin
  FHitText.Free;
  inherited Destroy;
end;

function TCoverageReader.Read(const AXml: string): TCoverageReport;
begin
  FResult := Default(TCoverageReport);
  FCursor.Init(AXml);
  while FCursor.Next do
  begin
    case FCursor.Kind of
      TXmlNodeKind.StartTag:
        OpenElement(LowerCase(FCursor.Name));
      TXmlNodeKind.EndTag:
        CloseElement(LowerCase(FCursor.Name));
      TXmlNodeKind.Text:
        if FInHitFile then
        begin
          FHitText.Append(FCursor.Value);
        end;
      TXmlNodeKind.Done: ;
    end;
  end;
  // Zeilen mit Durchläufen (linehits) gehen den Ja/Nein-Zeilen von JaCoCo vor.
  if (FResult.Format = TCoverageFormat.None) and (Length(FJacocoFiles) > 0) then
  begin
    FResult.Format := TCoverageFormat.JaCoCo;
    FResult.Files := FJacocoFiles;
  end;
  if FResult.Format = TCoverageFormat.None then
  begin
    if FIsReport and FDccSeen then
    begin
      FResult.Format := TCoverageFormat.DelphiCodeCoverage;
      FResult.Problem := TCoverageProblem.NoLines;
    end
    else
    begin
      FResult.Problem := TCoverageProblem.NotAReport;
    end;
  end;
  Result := FResult;
end;

end.
