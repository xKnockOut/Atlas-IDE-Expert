unit Atlas.Core.Debug.DataBreakWatch;

// Ablauf von „Anhalten bei Datenzugriff“ (#870) ohne IDE, prüfbar: ob ein Halt
// neu ist, was Atlas an einer Haltestelle auswertet und wie es entscheidet.
// Atlas.IDE.Debug.DataBreak fragt Debugger und Server.
// - Neuer Halt: Das Programm lief seit dem letzten Weiterlaufen, steht an
//   einer anderen Stelle, oder steht nach dem Weiterlaufen noch eine Weile an
//   derselben (dieselbe Zeile in einer Schleife, ohne dass der Takt das Laufen
//   gesehen hat). Wo Atlas angehalten hat oder der Benutzer steht, ist nie neu,
//   bis das Programm wieder läuft.
// - Auswertung: Text (SQL bzw. URL) als Zeichenkette, HTTP-Methode aus dem
//   Namen des Aufrufs oder dem Ausdruck der Klasse, SQL-Parameter als
//   „Name=Wert“. Was sich nicht auswerten lässt, zählt als Treffer.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.DataBreak;

type
  /// <summary>Wertet AExpression im angehaltenen Programm aus; False bei Fehler.</summary>
  TAtlasDataEvaluate = reference to function(const AExpression: string; out AValue: string): Boolean;

  TAtlasDataWatch = record
    Active: Boolean;
    /// <summary>Lief das Programm seit dem letzten Weiterlaufen bzw. Halt?</summary>
    SeenRunning: Boolean;
    /// <summary>Steht das Programm an LastFile/LastLine, weil Atlas oder der Benutzer es dort hält?</summary>
    Holding: Boolean;
    LastFile: string;
    LastLine: Integer;
    ResumedAt: UInt64;
    /// <summary>Beobachtung beginnt; das Programm steht nicht oder an AFileName/ALine (ALine -1: läuft).</summary>
    procedure Start(const AFileName: string; ALine: Integer);
    /// <summary>Atlas lässt das Programm an AFileName/ALine zur Zeit ANow weiterlaufen.</summary>
    procedure Resumed(const AFileName: string; ALine: Integer; ANow: UInt64);
    /// <summary>Programm steht an AFileName/ALine und bleibt dort, bis es wieder läuft.</summary>
    procedure Held(const AFileName: string; ALine: Integer);
    procedure Running;
    function StoppedAnew(const AFileName: string; ALine: Integer; ANow: UInt64): Boolean;
  end;

  TAtlasDataVerdict = record
    Outcome: TAtlasDataOutcome;
    /// <summary>Stelle (Index in den Stellen der Antwort), -1 ohne.</summary>
    Site: Integer;
    Values: TAtlasDataValues;
  end;

  TAtlasDataBreakWatch = class
  public const
    /// <summary>Steht das Programm so lange nach dem Weiterlaufen an derselben Stelle, hielt es dort erneut.
    /// </summary>
    cSameStopMs = 500;
  private
    class function Text(const AExpression: string; const AEvaluate: TAtlasDataEvaluate; out AText: string): Boolean;
      static;
    class function HttpMethod(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
      const AEvaluate: TAtlasDataEvaluate): string; static;
    class function Params(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
      const AEvaluate: TAtlasDataEvaluate): TArray<string>; static;
  public
    /// <summary>Text, HTTP-Methode und Parameter der Stelle ASite im angehaltenen Programm.</summary>
    class function Values(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
      const AEvaluate: TAtlasDataEvaluate): TAtlasDataValues; static;
    /// <summary>Entscheidung an der Haltestelle ALocation: die erste Stelle, die anhält oder protokolliert; sonst
    /// still weiter.</summary>
    class function Judge(const AChoice: TAtlasDataChoice; const ASites: TArray<TAtlasDataSite>;
      const AClasses: TArray<TAtlasDataClass>; const ALocation: TAtlasDataLocation;
      const AEvaluate: TAtlasDataEvaluate): TAtlasDataVerdict; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Debug.DataBreakPatterns;

{ TAtlasDataWatch }

procedure TAtlasDataWatch.Start(const AFileName: string; ALine: Integer);
begin
  Active := True;
  ResumedAt := 0;
  if ALine < 0 then
  begin
    LastFile := '';
    LastLine := -1;
    Holding := False;
    SeenRunning := True;
  end
  else
  begin
    Held(AFileName, ALine);
  end;
end;

procedure TAtlasDataWatch.Resumed(const AFileName: string; ALine: Integer; ANow: UInt64);
begin
  LastFile := AFileName;
  LastLine := ALine;
  ResumedAt := ANow;
  Holding := False;
  SeenRunning := False;
end;

procedure TAtlasDataWatch.Held(const AFileName: string; ALine: Integer);
begin
  LastFile := AFileName;
  LastLine := ALine;
  Holding := True;
  SeenRunning := False;
end;

procedure TAtlasDataWatch.Running;
begin
  SeenRunning := True;
  Holding := False;
end;

function TAtlasDataWatch.StoppedAnew(const AFileName: string; ALine: Integer; ANow: UInt64): Boolean;
begin
  if SeenRunning or (ALine <> LastLine) or not SameText(AFileName, LastFile) then
  begin
    Result := True;
  end
  else if Holding then
  begin
    Result := False;
  end
  else
  begin
    Result := ANow >= ResumedAt + TAtlasDataBreakWatch.cSameStopMs;
  end;
end;

{ TAtlasDataBreakWatch }

class function TAtlasDataBreakWatch.Text(const AExpression: string; const AEvaluate: TAtlasDataEvaluate;
  out AText: string): Boolean;
var
  mValue: string;
begin
  AText := '';
  Result := (AExpression <> '') and AEvaluate(AExpression, mValue) and
    TAtlasDataPatterns.DebuggerString(mValue, AText);
end;

class function TAtlasDataBreakWatch.HttpMethod(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
  const AEvaluate: TAtlasDataEvaluate): string;
var
  mExpression, mValue: string;
begin
  mExpression := TAtlasDataBreak.MethodExpression(ASite, AClass);
  if mExpression = '' then
  begin
    Exit(TAtlasDataPatterns.HttpMethodOf(ASite.Method));
  end;
  Result := '';
  if AEvaluate(mExpression, mValue) then
  begin
    Result := TAtlasDataPatterns.HttpMethodOf(mValue);
  end;
end;

class function TAtlasDataBreakWatch.Params(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
  const AEvaluate: TAtlasDataEvaluate): TArray<string>;
var
  mExpression, mValue, mName: string;
  mCount, mIndex: Integer;
begin
  Result := nil;
  mExpression := TAtlasDataBreak.ParamCountExpression(ASite, AClass);
  if (mExpression = '') or not AEvaluate(mExpression, mValue) or not TryStrToInt(Trim(mValue), mCount) then
  begin
    Exit;
  end;
  for mIndex := 0 to Min(mCount, TAtlasDataBreak.cMaxParams) - 1 do
  begin
    if not Text(TAtlasDataBreak.ParamNameExpression(ASite, AClass, mIndex), AEvaluate, mName) or
      not AEvaluate(TAtlasDataBreak.ParamValueExpression(ASite, AClass, mIndex), mValue) then
    begin
      Exit;
    end;
    Result := Result + [mName + '=' + Trim(mValue)];
  end;
end;

class function TAtlasDataBreakWatch.Values(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
  const AEvaluate: TAtlasDataEvaluate): TAtlasDataValues;
begin
  Result := Default(TAtlasDataValues);
  Result.Evaluated := Text(TAtlasDataBreak.TextExpression(ASite, AClass), AEvaluate, Result.Text);
  if not Result.Evaluated then
  begin
    Exit;
  end;
  if ASite.Kind = TAtlasDataKind.Http then
  begin
    Result.HttpMethod := HttpMethod(ASite, AClass, AEvaluate);
    // Ohne Methode lässt sich ein Muster mit Methoden nicht prüfen: lieber anhalten.
    Result.Evaluated := Result.HttpMethod <> '';
  end
  else
  begin
    Result.Params := Params(ASite, AClass, AEvaluate);
  end;
end;

class function TAtlasDataBreakWatch.Judge(const AChoice: TAtlasDataChoice; const ASites: TArray<TAtlasDataSite>;
  const AClasses: TArray<TAtlasDataClass>; const ALocation: TAtlasDataLocation;
  const AEvaluate: TAtlasDataEvaluate): TAtlasDataVerdict;
var
  mItem: Integer;
  mClass: TAtlasDataClass;
  mValues: TAtlasDataValues;
  mOutcome: TAtlasDataOutcome;
begin
  Result := Default(TAtlasDataVerdict);
  Result.Outcome := TAtlasDataOutcome.Continue;
  Result.Site := -1;
  for mItem in ALocation.Items do
  begin
    if not (ASites[mItem].Kind in AChoice.Kinds) then
    begin
      Continue;
    end;
    mValues := Default(TAtlasDataValues);
    if TAtlasDataBreak.ClassOf(AClasses, ASites[mItem].WatchedClass, mClass) then
    begin
      mValues := Values(ASites[mItem], mClass, AEvaluate);
    end;
    mOutcome := TAtlasDataBreak.Decide(AChoice, ASites[mItem], mValues);
    if mOutcome <> TAtlasDataOutcome.Continue then
    begin
      Result.Outcome := mOutcome;
      Result.Site := mItem;
      Result.Values := mValues;
      Exit;
    end;
  end;
end;

end.
