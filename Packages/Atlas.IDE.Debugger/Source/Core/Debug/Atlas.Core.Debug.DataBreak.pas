unit Atlas.Core.Debug.DataBreak;

// Anhalten bei Datenzugriff (#870), Kern ohne IDE: welche Klassen beobachtet
// werden, Argumente und Antwort von atlas.server.dataAccessSites, Haltestellen,
// Ausdrücke für die Auswertung beim Halt und die Entscheidung, ob Atlas
// anhält, protokolliert oder still weiterlaufen lässt.
// - Bekannte Klassen (FireDAC, dbExpress, ADO, Zeos, THTTPClient,
//   TNetHTTPClient, TRESTRequest, TIdHTTP) tragen ihre Methoden und
//   Ausdrücke; eigene aus debug.dataBreaks.classes (TMeineAbfrage=sql) die
//   allgemeinen ihrer Art.
// - Ausdrücke: %R steht für den Empfänger, %I für den Index eines Parameters.
//   Steht der Text im ersten Argument (FConn.ExecSQL('…'),
//   Client.Post(Url, …)), wertet Atlas das Argument aus, sonst den Ausdruck der
//   Klasse (qryKunde.SQL.Text bzw. bei TRESTRequest die volle URL).
// - Je Datei und Zeile ein Haltepunkt; mehrere Aufrufe einer Zeile teilen ihn.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.DataBreakClasses,
  Atlas.Core.Debug.DataBreakPatterns;

type
  {$SCOPEDENUMS ON}
  TAtlasDataKind = (Sql, Http);
  /// <summary>Was beim Halt mit passendem Text geschieht: anhalten mit Leiste oder nur protokollieren.</summary>
  TAtlasDataMode = (Stop, Log);
  /// <summary>Ergebnis an einer Haltestelle: still weiter, anhalten oder protokollieren und weiter.</summary>
  TAtlasDataOutcome = (Continue, Stop, Log);
  {$SCOPEDENUMS OFF}
  TAtlasDataKinds = set of TAtlasDataKind;

  TAtlasDataClass = record
    Name: string;
    Kind: TAtlasDataKind;
    Methods: TArray<string>;
    /// <summary>Text (SQL bzw. URL) ohne Argument, mit %R für den Empfänger.</summary>
    TextExpression: string;
    /// <summary>Methoden, deren erstes Argument der Text ist; leer = keine.</summary>
    TextArgumentMethods: TArray<string>;
    /// <summary>HTTP-Methode, wenn sie nicht im Namen des Aufrufs steht (TRESTRequest).</summary>
    MethodExpression: string;
    /// <summary>SQL-Parameter: Anzahl, Name und Wert (%I = Index); leer = keine.</summary>
    ParamCountExpression: string;
    ParamNameExpression: string;
    ParamValueExpression: string;
  end;

  TAtlasDataSite = record
    FileName: string;
    /// <summary>Zeile (ab 0) des Methodennamens.</summary>
    Line: Integer;
    /// <summary>Zeile (ab 0) des Haltepunkts.</summary>
    BreakLine: Integer;
    WatchedClass: string;
    Kind: TAtlasDataKind;
    Method: string;
    Receiver: string;
    ReceiverType: string;
    Arguments: TArray<string>;
    Routine: string;
  end;

  TAtlasDataAnswer = record
    Sites: TArray<TAtlasDataSite>;
    Unresolved: Integer;
  end;

  TAtlasDataLocation = record
    FileName: string;
    Line: Integer;
    /// <summary>Indizes der Stellen in dieser Zeile.</summary>
    Sites: TArray<Integer>;
  end;

  TAtlasDataChoice = record
    Kinds: TAtlasDataKinds;
    SqlPattern: string;
    /// <summary>„POST */api/auftrag*“; Methoden vorn sind wahlweise.</summary>
    HttpPattern: string;
    IgnoreCase: Boolean;
    Mode: TAtlasDataMode;
    class function Defaults: TAtlasDataChoice; static;
  end;

  /// <summary>Was Atlas an einer Stelle ausgewertet hat.</summary>
  TAtlasDataValues = record
    /// <summary>Text auswertbar? Sonst gilt die Stelle als Treffer (lieber einmal zu oft anhalten).</summary>
    Evaluated: Boolean;
    /// <summary>SQL-Text bzw. URL.</summary>
    Text: string;
    /// <summary>HTTP-Methode in Großbuchstaben.</summary>
    HttpMethod: string;
    /// <summary>SQL-Parameter als „Name=Wert“.</summary>
    Params: TArray<string>;
  end;

  TAtlasDataBreak = class
  public const
    cCommand = 'atlas.server.dataAccessSites';
    cKindNames: array[TAtlasDataKind] of string = ('sql', 'http');
    /// <summary>Mehr SQL-Parameter wertet Atlas nicht aus.</summary>
    cMaxParams = 20;
    /// <summary>Ab so vielen Haltepunkten weist Atlas auf die Laufzeit hin.</summary>
    cManyBreakpoints = 200;
  private
    class function KnownClass(const AName: string; out AClass: TAtlasDataClass): Boolean; static;
    class function GenericClass(const AName: string; AKind: TAtlasDataKind): TAtlasDataClass; static;
    class function KindOf(const AText: string; out AKind: TAtlasDataKind): Boolean; static;
    class function ReadSite(AItem: TJSONObject; out ASite: TAtlasDataSite): Boolean; static;
    class function Fill(const ATemplate, AReceiver: string; AIndex: Integer): string; static;
  public
    /// <summary>Alle bekannten Klassen in der Reihenfolge der Vorgabe.</summary>
    class function KnownClasses: TArray<TAtlasDataClass>; static;
    /// <summary>Klassen aus den Einträgen der Einstellung; unbekannte ohne Art landen in ASkipped.</summary>
    class function Classes(const AEntries: TArray<TAtlasDataBreakClassEntry>;
      out ASkipped: TArray<string>): TArray<TAtlasDataClass>; static;
    /// <summary>Klasse AName aus AClasses; False ohne.</summary>
    class function ClassOf(const AClasses: TArray<TAtlasDataClass>; const AName: string;
      out AClass: TAtlasDataClass): Boolean; static;
    /// <summary>Argumente für den Befehl: [uri bzw. null, classes].</summary>
    class function Arguments(const AProjectUri: string; const AClasses: TArray<TAtlasDataClass>): string; static;
    class function ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasDataAnswer): Boolean; static;
    /// <summary>Zahl der Stellen der Art AKind.</summary>
    class function CountOf(const ASites: TArray<TAtlasDataSite>; AKind: TAtlasDataKind): Integer; static;
    /// <summary>Haltestellen der Stellen mit einer Art aus AKinds, je Datei und Zeile eine, in Reihenfolge der
    /// Stellen.</summary>
    class function Locations(const ASites: TArray<TAtlasDataSite>;
      AKinds: TAtlasDataKinds): TArray<TAtlasDataLocation>; static;
    /// <summary>Haltestelle an AFileName/ALine; -1 ohne.</summary>
    class function LocationAt(const ALocations: TArray<TAtlasDataLocation>; const AFileName: string;
      ALine: Integer): Integer; static;
    /// <summary>Ausdruck für SQL-Text bzw. URL der Stelle; '' ohne (Argument zu lang, Klasse ohne Ausdruck).
    /// </summary>
    class function TextExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass): string; static;
    /// <summary>Ausdruck für die HTTP-Methode; '' = sie steht im Namen des Aufrufs (HttpMethodOf).</summary>
    class function MethodExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass): string; static;
    /// <summary>Ausdrücke für die SQL-Parameter; '' ohne. Nicht, wenn der Text aus dem Argument kommt.</summary>
    class function ParamCountExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass): string;
      static;
    class function ParamNameExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
      AIndex: Integer): string; static;
    class function ParamValueExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
      AIndex: Integer): string; static;
    /// <summary>Anhalten, protokollieren oder still weiter? Nicht auswertbare Texte zählen als Treffer.</summary>
    class function Decide(const AChoice: TAtlasDataChoice; const ASite: TAtlasDataSite;
      const AValues: TAtlasDataValues): TAtlasDataOutcome; static;
    /// <summary>„Kunde.pas:43 · TfrmKunde.Speichern · qryKunde.ExecSQL“.</summary>
    class function Place(const ASite: TAtlasDataSite): string; static;
    /// <summary>„UPDATE Kunden SET Name = :Name [Name='A']“ bzw. „POST http://…“; ANotEvaluated ohne Text.
    /// </summary>
    class function Detail(const ASite: TAtlasDataSite; const AValues: TAtlasDataValues;
      const ANotEvaluated: string): string; static;
    /// <summary>Zeile für das Ereignisprotokoll: „[SQL] Ort: Detail“.</summary>
    class function LogLine(const ASite: TAtlasDataSite; const AValues: TAtlasDataValues;
      const ANotEvaluated: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Text.Json;

type
  TKnownClass = record
    Name: string;
    Kind: TAtlasDataKind;
    Methods: string;
    TextExpression: string;
    TextArgumentMethods: string;
    MethodExpression: string;
    Params: string;
  end;

const
  // Params: Sammlung der Parameter („Params“ bzw. „Parameters“) und Eigenschaft des Werts.
  cFireDacParams = 'Params|AsString';
  cAdoParams = 'Parameters|Value';
  cKnown: array[0..17] of TKnownClass = (
    (Name: 'TFDQuery'; Kind: TAtlasDataKind.Sql; Methods: 'Open,ExecSQL,Execute'; TextExpression: '%R.SQL.Text';
      TextArgumentMethods: 'Open,ExecSQL'; MethodExpression: ''; Params: cFireDacParams),
    (Name: 'TFDCommand'; Kind: TAtlasDataKind.Sql; Methods: 'Open,Execute'; TextExpression: '%R.CommandText.Text';
      TextArgumentMethods: 'Open'; MethodExpression: ''; Params: cFireDacParams),
    (Name: 'TFDConnection'; Kind: TAtlasDataKind.Sql; Methods: 'ExecSQL,ExecSQLScalar'; TextExpression: '';
      TextArgumentMethods: 'ExecSQL,ExecSQLScalar'; MethodExpression: ''; Params: ''),
    (Name: 'TFDStoredProc'; Kind: TAtlasDataKind.Sql; Methods: 'Open,ExecProc,Execute';
      TextExpression: '%R.StoredProcName'; TextArgumentMethods: ''; MethodExpression: ''; Params: cFireDacParams),
    (Name: 'TSQLQuery'; Kind: TAtlasDataKind.Sql; Methods: 'Open,ExecSQL'; TextExpression: '%R.SQL.Text';
      TextArgumentMethods: ''; MethodExpression: ''; Params: cFireDacParams),
    (Name: 'TSQLDataSet'; Kind: TAtlasDataKind.Sql; Methods: 'Open,ExecSQL'; TextExpression: '%R.CommandText';
      TextArgumentMethods: ''; MethodExpression: ''; Params: cFireDacParams),
    (Name: 'TSQLConnection'; Kind: TAtlasDataKind.Sql; Methods: 'Execute,ExecuteDirect'; TextExpression: '';
      TextArgumentMethods: 'Execute,ExecuteDirect'; MethodExpression: ''; Params: ''),
    (Name: 'TADOQuery'; Kind: TAtlasDataKind.Sql; Methods: 'Open,ExecSQL'; TextExpression: '%R.SQL.Text';
      TextArgumentMethods: ''; MethodExpression: ''; Params: cAdoParams),
    (Name: 'TADOCommand'; Kind: TAtlasDataKind.Sql; Methods: 'Execute'; TextExpression: '%R.CommandText';
      TextArgumentMethods: ''; MethodExpression: ''; Params: cAdoParams),
    (Name: 'TADOConnection'; Kind: TAtlasDataKind.Sql; Methods: 'Execute'; TextExpression: '';
      TextArgumentMethods: 'Execute'; MethodExpression: ''; Params: ''),
    (Name: 'TADODataSet'; Kind: TAtlasDataKind.Sql; Methods: 'Open'; TextExpression: '%R.CommandText';
      TextArgumentMethods: ''; MethodExpression: ''; Params: cAdoParams),
    (Name: 'TZQuery'; Kind: TAtlasDataKind.Sql; Methods: 'Open,ExecSQL'; TextExpression: '%R.SQL.Text';
      TextArgumentMethods: ''; MethodExpression: ''; Params: cFireDacParams),
    (Name: 'TZReadOnlyQuery'; Kind: TAtlasDataKind.Sql; Methods: 'Open'; TextExpression: '%R.SQL.Text';
      TextArgumentMethods: ''; MethodExpression: ''; Params: cFireDacParams),
    (Name: 'TZConnection'; Kind: TAtlasDataKind.Sql; Methods: 'ExecuteDirect'; TextExpression: '';
      TextArgumentMethods: 'ExecuteDirect'; MethodExpression: ''; Params: ''),
    (Name: 'THTTPClient'; Kind: TAtlasDataKind.Http; Methods: 'Get,Post,Put,Delete,Patch,Head';
      TextExpression: ''; TextArgumentMethods: 'Get,Post,Put,Delete,Patch,Head'; MethodExpression: '';
      Params: ''),
    (Name: 'TNetHTTPClient'; Kind: TAtlasDataKind.Http; Methods: 'Get,Post,Put,Delete,Patch,Head';
      TextExpression: ''; TextArgumentMethods: 'Get,Post,Put,Delete,Patch,Head'; MethodExpression: '';
      Params: ''),
    (Name: 'TRESTRequest'; Kind: TAtlasDataKind.Http; Methods: 'Execute,ExecuteAsync';
      TextExpression: '%R.GetFullRequestURL(True)'; TextArgumentMethods: ''; MethodExpression: '%R.Method';
      Params: ''),
    (Name: 'TIdHTTP'; Kind: TAtlasDataKind.Http; Methods: 'Get,Post,Put,Delete,Patch,Head';
      TextExpression: ''; TextArgumentMethods: 'Get,Post,Put,Delete,Patch,Head'; MethodExpression: '';
      Params: ''));
  // Allgemeine Fassung für eigene Klassen je Art.
  cGenericMethods: array[TAtlasDataKind] of string = ('Open,ExecSQL,Execute,ExecSQLScalar',
    'Get,Post,Put,Delete,Patch,Head,Execute');
  cGenericText: array[TAtlasDataKind] of string = ('%R.SQL.Text', '');
  cGenericArgumentMethods: array[TAtlasDataKind] of string = ('ExecSQLScalar',
    'Get,Post,Put,Delete,Patch,Head');
  cLogPrefix: array[TAtlasDataKind] of string = ('[SQL]', '[HTTP]');

function Names(const AText: string): TArray<string>;
begin
  Result := nil;
  if AText <> '' then
  begin
    Result := AText.Split([',']);
  end;
end;

function FromKnown(const AKnown: TKnownClass): TAtlasDataClass;
var
  mParts: TArray<string>;
begin
  Result := Default(TAtlasDataClass);
  Result.Name := AKnown.Name;
  Result.Kind := AKnown.Kind;
  Result.Methods := Names(AKnown.Methods);
  Result.TextExpression := AKnown.TextExpression;
  Result.TextArgumentMethods := Names(AKnown.TextArgumentMethods);
  Result.MethodExpression := AKnown.MethodExpression;
  if AKnown.Params <> '' then
  begin
    mParts := AKnown.Params.Split(['|']);
    Result.ParamCountExpression := '%R.' + mParts[0] + '.Count';
    Result.ParamNameExpression := '%R.' + mParts[0] + '[%I].Name';
    Result.ParamValueExpression := '%R.' + mParts[0] + '[%I].' + mParts[1];
  end;
end;

{ TAtlasDataChoice }

class function TAtlasDataChoice.Defaults: TAtlasDataChoice;
begin
  Result := Default(TAtlasDataChoice);
  Result.Kinds := [TAtlasDataKind.Sql, TAtlasDataKind.Http];
  Result.IgnoreCase := True;
  Result.Mode := TAtlasDataMode.Stop;
end;

{ TAtlasDataBreak }

class function TAtlasDataBreak.KnownClass(const AName: string; out AClass: TAtlasDataClass): Boolean;
var
  mKnown: TKnownClass;
begin
  for mKnown in cKnown do
  begin
    if SameText(mKnown.Name, AName) then
    begin
      AClass := FromKnown(mKnown);
      Exit(True);
    end;
  end;
  AClass := Default(TAtlasDataClass);
  Result := False;
end;

class function TAtlasDataBreak.GenericClass(const AName: string; AKind: TAtlasDataKind): TAtlasDataClass;
begin
  Result := Default(TAtlasDataClass);
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Methods := Names(cGenericMethods[AKind]);
  Result.TextExpression := cGenericText[AKind];
  Result.TextArgumentMethods := Names(cGenericArgumentMethods[AKind]);
  if AKind = TAtlasDataKind.Sql then
  begin
    Result.ParamCountExpression := '%R.Params.Count';
    Result.ParamNameExpression := '%R.Params[%I].Name';
    Result.ParamValueExpression := '%R.Params[%I].AsString';
  end;
end;

class function TAtlasDataBreak.KindOf(const AText: string; out AKind: TAtlasDataKind): Boolean;
var
  mKind: TAtlasDataKind;
begin
  for mKind := Low(TAtlasDataKind) to High(TAtlasDataKind) do
  begin
    if SameText(cKindNames[mKind], AText) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TAtlasDataKind.Sql;
  Result := False;
end;

class function TAtlasDataBreak.KnownClasses: TArray<TAtlasDataClass>;
var
  mKnown: TKnownClass;
begin
  Result := nil;
  for mKnown in cKnown do
  begin
    Result := Result + [FromKnown(mKnown)];
  end;
end;

class function TAtlasDataBreak.Classes(const AEntries: TArray<TAtlasDataBreakClassEntry>;
  out ASkipped: TArray<string>): TArray<TAtlasDataClass>;
var
  mEntry: TAtlasDataBreakClassEntry;
  mClass: TAtlasDataClass;
  mKind: TAtlasDataKind;
begin
  Result := nil;
  ASkipped := nil;
  for mEntry in AEntries do
  begin
    // Eine Art in der Einstellung gilt auch für bekannte Klassen: Dann zählt die allgemeine Fassung.
    if KindOf(mEntry.Kind, mKind) then
    begin
      Result := Result + [GenericClass(mEntry.Name, mKind)];
    end
    else if KnownClass(mEntry.Name, mClass) then
    begin
      Result := Result + [mClass];
    end
    else
    begin
      ASkipped := ASkipped + [mEntry.Name];
    end;
  end;
end;

class function TAtlasDataBreak.ClassOf(const AClasses: TArray<TAtlasDataClass>; const AName: string;
  out AClass: TAtlasDataClass): Boolean;
var
  mClass: TAtlasDataClass;
begin
  for mClass in AClasses do
  begin
    if SameText(mClass.Name, AName) then
    begin
      AClass := mClass;
      Exit(True);
    end;
  end;
  AClass := Default(TAtlasDataClass);
  Result := False;
end;

class function TAtlasDataBreak.Arguments(const AProjectUri: string; const AClasses: TArray<TAtlasDataClass>): string;
var
  mRoot: TJSONArray;
  mList: TJSONArray;
  mItem: TJSONObject;
  mClass: TAtlasDataClass;
begin
  mRoot := TJSONArray.Create;
  try
    if AProjectUri = '' then
    begin
      mRoot.AddElement(TJSONNull.Create);
    end
    else
    begin
      mRoot.Add(AProjectUri);
    end;
    mList := TJSONArray.Create;
    mRoot.AddElement(mList);
    for mClass in AClasses do
    begin
      mItem := TJSONObject.Create;
      mList.AddElement(mItem);
      mItem.AddPair('name', mClass.Name);
      mItem.AddPair('kind', cKindNames[mClass.Kind]);
      mItem.AddPair('methods', TJsonBuild.Strings(mClass.Methods));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasDataBreak.ReadSite(AItem: TJSONObject; out ASite: TAtlasDataSite): Boolean;
begin
  ASite := Default(TAtlasDataSite);
  ASite.FileName := TJsonRead.Text(AItem, 'file');
  ASite.Line := TJsonRead.IntOr(AItem, 'line', -1);
  ASite.BreakLine := TJsonRead.IntOr(AItem, 'breakLine', ASite.Line);
  ASite.WatchedClass := TJsonRead.Text(AItem, 'class');
  ASite.Method := TJsonRead.Text(AItem, 'method');
  ASite.Receiver := TJsonRead.Text(AItem, 'receiver');
  ASite.ReceiverType := TJsonRead.Text(AItem, 'receiverType');
  ASite.Arguments := TJsonRead.Strings(AItem, 'arguments');
  ASite.Routine := TJsonRead.Text(AItem, 'routine');
  Result := KindOf(TJsonRead.Text(AItem, 'kind'), ASite.Kind) and (ASite.FileName <> '') and
    (ASite.BreakLine >= 0);
end;

class function TAtlasDataBreak.ReadAnswer(AJson: TJSONValue; out AAnswer: TAtlasDataAnswer): Boolean;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mItem: TJSONValue;
  mSite: TAtlasDataSite;
begin
  AAnswer := Default(TAtlasDataAnswer);
  mRoot := TJsonRead.AsObject(AJson);
  mList := TJsonRead.Items(mRoot, 'sites');
  Result := mList <> nil;
  if not Result then
  begin
    Exit;
  end;
  for mItem in mList do
  begin
    if (mItem is TJSONObject) and ReadSite(TJSONObject(mItem), mSite) then
    begin
      AAnswer.Sites := AAnswer.Sites + [mSite];
    end;
  end;
  AAnswer.Unresolved := TJsonRead.IntOr(mRoot, 'unresolved', 0);
end;

class function TAtlasDataBreak.CountOf(const ASites: TArray<TAtlasDataSite>; AKind: TAtlasDataKind): Integer;
var
  mSite: TAtlasDataSite;
begin
  Result := 0;
  for mSite in ASites do
  begin
    if mSite.Kind = AKind then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasDataBreak.Locations(const ASites: TArray<TAtlasDataSite>;
  AKinds: TAtlasDataKinds): TArray<TAtlasDataLocation>;
var
  mIndex, mFound: Integer;
  mLocation: TAtlasDataLocation;
begin
  Result := nil;
  for mIndex := 0 to High(ASites) do
  begin
    if not (ASites[mIndex].Kind in AKinds) then
    begin
      Continue;
    end;
    mFound := LocationAt(Result, ASites[mIndex].FileName, ASites[mIndex].BreakLine);
    if mFound >= 0 then
    begin
      Result[mFound].Sites := Result[mFound].Sites + [mIndex];
      Continue;
    end;
    mLocation := Default(TAtlasDataLocation);
    mLocation.FileName := ASites[mIndex].FileName;
    mLocation.Line := ASites[mIndex].BreakLine;
    mLocation.Sites := [mIndex];
    Result := Result + [mLocation];
  end;
end;

class function TAtlasDataBreak.LocationAt(const ALocations: TArray<TAtlasDataLocation>; const AFileName: string;
  ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALocations) do
  begin
    if (ALocations[mIndex].Line = ALine) and SameText(ALocations[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasDataBreak.Fill(const ATemplate, AReceiver: string; AIndex: Integer): string;
begin
  Result := '';
  if (ATemplate <> '') and (AReceiver <> '') then
  begin
    Result := ATemplate.Replace('%R', AReceiver).Replace('%I', IntToStr(AIndex));
  end;
end;

function TextFromArgument(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass): Boolean;
begin
  Result := (Length(ASite.Arguments) > 0) and (IndexText(ASite.Method, AClass.TextArgumentMethods) >= 0);
end;

class function TAtlasDataBreak.TextExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass): string;
begin
  if TextFromArgument(ASite, AClass) then
  begin
    // Zu langes Argument liefert der Server leer: dann nicht auswertbar.
    Result := ASite.Arguments[0];
  end
  else
  begin
    Result := Fill(AClass.TextExpression, ASite.Receiver, 0);
  end;
end;

class function TAtlasDataBreak.MethodExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass): string;
begin
  Result := Fill(AClass.MethodExpression, ASite.Receiver, 0);
end;

class function TAtlasDataBreak.ParamCountExpression(const ASite: TAtlasDataSite;
  const AClass: TAtlasDataClass): string;
begin
  Result := '';
  if not TextFromArgument(ASite, AClass) then
  begin
    Result := Fill(AClass.ParamCountExpression, ASite.Receiver, 0);
  end;
end;

class function TAtlasDataBreak.ParamNameExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
  AIndex: Integer): string;
begin
  Result := Fill(AClass.ParamNameExpression, ASite.Receiver, AIndex);
end;

class function TAtlasDataBreak.ParamValueExpression(const ASite: TAtlasDataSite; const AClass: TAtlasDataClass;
  AIndex: Integer): string;
begin
  Result := Fill(AClass.ParamValueExpression, ASite.Receiver, AIndex);
end;

class function TAtlasDataBreak.Decide(const AChoice: TAtlasDataChoice; const ASite: TAtlasDataSite;
  const AValues: TAtlasDataValues): TAtlasDataOutcome;
var
  mMatches: Boolean;
begin
  if not (ASite.Kind in AChoice.Kinds) then
  begin
    Exit(TAtlasDataOutcome.Continue);
  end;
  if not AValues.Evaluated then
  begin
    mMatches := True;
  end
  else if ASite.Kind = TAtlasDataKind.Sql then
  begin
    mMatches := TAtlasDataPatterns.Like(AChoice.SqlPattern, AValues.Text, AChoice.IgnoreCase);
  end
  else
  begin
    mMatches := TAtlasDataPatterns.HttpMatches(TAtlasDataPatterns.ParseHttp(AChoice.HttpPattern),
      AValues.HttpMethod, AValues.Text, AChoice.IgnoreCase);
  end;
  if not mMatches then
  begin
    Result := TAtlasDataOutcome.Continue;
  end
  else if AChoice.Mode = TAtlasDataMode.Log then
  begin
    Result := TAtlasDataOutcome.Log;
  end
  else
  begin
    Result := TAtlasDataOutcome.Stop;
  end;
end;

class function TAtlasDataBreak.Place(const ASite: TAtlasDataSite): string;
begin
  Result := Format('%s:%d', [ExtractFileName(ASite.FileName), ASite.Line + 1]);
  if ASite.Routine <> '' then
  begin
    Result := Result + ' · ' + ASite.Routine;
  end;
  Result := Result + ' · ' + ASite.Receiver + '.' + ASite.Method;
end;

class function TAtlasDataBreak.Detail(const ASite: TAtlasDataSite; const AValues: TAtlasDataValues;
  const ANotEvaluated: string): string;
begin
  if not AValues.Evaluated then
  begin
    Exit(ANotEvaluated);
  end;
  Result := TAtlasDataPatterns.Squeeze(AValues.Text);
  if ASite.Kind = TAtlasDataKind.Http then
  begin
    Result := Trim(AValues.HttpMethod + ' ' + Result);
  end
  else if Length(AValues.Params) > 0 then
  begin
    Result := Result + ' [' + string.Join(', ', AValues.Params) + ']';
  end;
end;

class function TAtlasDataBreak.LogLine(const ASite: TAtlasDataSite; const AValues: TAtlasDataValues;
  const ANotEvaluated: string): string;
begin
  Result := cLogPrefix[ASite.Kind] + ' ' + Place(ASite) + ': ' + Detail(ASite, AValues, ANotEvaluated);
end;

end.
