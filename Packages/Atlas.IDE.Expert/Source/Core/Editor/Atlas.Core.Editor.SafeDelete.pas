unit Atlas.Core.Editor.SafeDelete;

// „Sicher löschen“ (#716), Kern im Plugin ohne VCL und ToolsAPI: Argumente
// für die Befehle des Servers (Alt+Entf baut [uri, position] selbst, die
// Code-Aktion liefert sie), die Antwort der Prüfung
// (atlas.server.safeDelete.prepare) und welche Rückfragen nötig sind:
// Überschreibungen und Folgeschritte nach der Einstellung ask, always oder
// never; Verwendungen (samt nicht mitgelöschter Überschreibungen) brauchen
// die Wahl Abbrechen, Anzeigen oder Trotzdem löschen; die Vorschau erscheint
// mit Verwendungen, bei einer ganzen Unit oder mit
// refactoring.safeDeletePreviewWhenUnused, sonst wird sofort gelöscht.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  TAtlasSafeDeleteUsage = record
    FileName: string;
    /// <summary>Ab 0.</summary>
    Line: Integer;
    Character: Integer;
    Text: string;
    /// <summary>code, form, interface, uses oder override.</summary>
    Kind: string;
  end;

  TAtlasSafeDeleteInfo = record
    /// <summary>Methode, Feld, …, Unit.</summary>
    Kind: string;
    Name: string;
    Title: string;
    Usages: TArray<TAtlasSafeDeleteUsage>;
    Overrides: TArray<TAtlasSafeDeleteUsage>;
    /// <summary>Was dadurch unbenutzt wird ("FCache", "uses Helpers").</summary>
    Cascade: TArray<string>;
    Warnings: TArray<string>;
    PreviewWhenUnused: Boolean;
    /// <summary>ask, always oder never.</summary>
    CascadeMode: string;
    OverridesMode: string;
    class function FromJson(const AValue: TJSONValue): TAtlasSafeDeleteInfo; static;
    function IsUnit: Boolean;
    /// <summary>Verwendungen, die gegen das Löschen sprechen; Überschreibungen nur, wenn sie bleiben.</summary>
    function Blocking(AIncludeOverrides: Boolean): TArray<TAtlasSafeDeleteUsage>;
    /// <summary>Vorschau statt sofort löschen?</summary>
    function NeedsPreview(AForced: Boolean): Boolean;
  end;

  {$SCOPEDENUMS ON}
  TAtlasSafeDeleteAnswer = (Ask, Always, Never);
  {$SCOPEDENUMS OFF}

  TAtlasSafeDelete = class
  public const
    ClientCommand = 'atlas.safeDelete';
    PrepareCommand = 'atlas.server.safeDelete.prepare';
    ApplyCommand = 'atlas.server.safeDelete';
    /// <summary>Alt+Entf.</summary>
    DefaultKey = $802E;
  public
    /// <summary>[uri, position].</summary>
    class function Arguments(const AUri: string; ALine, ACharacter: Integer): string; static;
    /// <summary>AArgumentsJson ([uri, position]) mit den Antworten als drittem Argument.</summary>
    class function ApplyArguments(const AArgumentsJson: string; AOverrides, ACascade, AForce: Boolean): string;
      static;
    /// <summary>ask, always, never; Unbekanntes gilt als ask.</summary>
    class function AnswerOf(const AMode: string): TAtlasSafeDeleteAnswer; static;
    /// <summary>Zeilen für eine Rückfrage: höchstens AMax, dann "… n weitere" über AMore (Format mit %d).</summary>
    class function Listing(const AItems: TArray<string>; AMax: Integer; const AMore: string): string; static;
  end;

implementation

function StringOf(const AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
    Result := AObject.GetValue(AName).Value;
end;

function UsagesOf(const AObject: TJSONObject; const AName: string): TArray<TAtlasSafeDeleteUsage>;
var
  Item: TJSONValue;
  Usage: TAtlasSafeDeleteUsage;
begin
  Result := nil;
  if not (AObject.GetValue(AName) is TJSONArray) then
    Exit;
  for Item in TJSONArray(AObject.GetValue(AName)) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Usage := Default(TAtlasSafeDeleteUsage);
    Usage.FileName := StringOf(TJSONObject(Item), 'file');
    TJSONObject(Item).TryGetValue<Integer>('line', Usage.Line);
    TJSONObject(Item).TryGetValue<Integer>('character', Usage.Character);
    Usage.Text := StringOf(TJSONObject(Item), 'text');
    Usage.Kind := StringOf(TJSONObject(Item), 'kind');
    Result := Result + [Usage];
  end;
end;

function StringsOf(const AObject: TJSONObject; const AName: string): TArray<string>;
var
  Item: TJSONValue;
begin
  Result := nil;
  if AObject.GetValue(AName) is TJSONArray then
    for Item in TJSONArray(AObject.GetValue(AName)) do
      Result := Result + [Item.Value];
end;

{ TAtlasSafeDeleteInfo }

class function TAtlasSafeDeleteInfo.FromJson(const AValue: TJSONValue): TAtlasSafeDeleteInfo;
var
  Answer: TJSONObject;
begin
  Result := Default(TAtlasSafeDeleteInfo);
  Result.CascadeMode := 'ask';
  Result.OverridesMode := 'ask';
  if not (AValue is TJSONObject) then
    Exit;
  Answer := TJSONObject(AValue);
  Result.Kind := StringOf(Answer, 'kind');
  Result.Name := StringOf(Answer, 'name');
  Result.Title := StringOf(Answer, 'title');
  Result.Usages := UsagesOf(Answer, 'usages');
  Result.Overrides := UsagesOf(Answer, 'overrides');
  Result.Cascade := StringsOf(Answer, 'cascade');
  Result.Warnings := StringsOf(Answer, 'warnings');
  Result.PreviewWhenUnused := (Answer.GetValue('previewWhenUnused') is TJSONBool) and
    TJSONBool(Answer.GetValue('previewWhenUnused')).AsBoolean;
  if StringOf(Answer, 'cascadeMode') <> '' then
    Result.CascadeMode := StringOf(Answer, 'cascadeMode');
  if StringOf(Answer, 'overridesMode') <> '' then
    Result.OverridesMode := StringOf(Answer, 'overridesMode');
end;

function TAtlasSafeDeleteInfo.IsUnit: Boolean;
begin
  Result := SameText(Kind, 'Unit');
end;

function TAtlasSafeDeleteInfo.Blocking(AIncludeOverrides: Boolean): TArray<TAtlasSafeDeleteUsage>;
begin
  Result := Usages;
  if not AIncludeOverrides then
    Result := Result + Overrides;
end;

function TAtlasSafeDeleteInfo.NeedsPreview(AForced: Boolean): Boolean;
begin
  Result := AForced or PreviewWhenUnused or IsUnit;
end;

{ TAtlasSafeDelete }

class function TAtlasSafeDelete.Arguments(const AUri: string; ALine, ACharacter: Integer): string;
var
  List: TJSONArray;
  Position: TJSONObject;
begin
  List := TJSONArray.Create;
  try
    List.Add(AUri);
    Position := TJSONObject.Create;
    Position.AddPair('line', TJSONNumber.Create(ALine));
    Position.AddPair('character', TJSONNumber.Create(ACharacter));
    List.AddElement(Position);
    Result := List.ToJSON;
  finally
    List.Free;
  end;
end;

class function TAtlasSafeDelete.ApplyArguments(const AArgumentsJson: string; AOverrides, ACascade,
  AForce: Boolean): string;
var
  Parsed: TJSONValue;
  List: TJSONArray;
  Choices: TJSONObject;
begin
  Parsed := TJSONObject.ParseJSONValue(AArgumentsJson);
  try
    if Parsed is TJSONArray then
    begin
      List := TJSONArray.Create;
      try
        // Nur uri und Position übernehmen, die Antworten kommen frisch dazu.
        if TJSONArray(Parsed).Count > 0 then
          List.AddElement(TJSONArray(Parsed).Items[0].Clone as TJSONValue);
        if TJSONArray(Parsed).Count > 1 then
          List.AddElement(TJSONArray(Parsed).Items[1].Clone as TJSONValue);
        Choices := TJSONObject.Create;
        Choices.AddPair('overrides', TJSONBool.Create(AOverrides));
        Choices.AddPair('cascade', TJSONBool.Create(ACascade));
        Choices.AddPair('force', TJSONBool.Create(AForce));
        List.AddElement(Choices);
        Result := List.ToJSON;
      finally
        List.Free;
      end;
    end
    else
      Result := AArgumentsJson;
  finally
    Parsed.Free;
  end;
end;

class function TAtlasSafeDelete.AnswerOf(const AMode: string): TAtlasSafeDeleteAnswer;
begin
  if SameText(AMode, 'always') then
    Result := TAtlasSafeDeleteAnswer.Always
  else if SameText(AMode, 'never') then
    Result := TAtlasSafeDeleteAnswer.Never
  else
    Result := TAtlasSafeDeleteAnswer.Ask;
end;

class function TAtlasSafeDelete.Listing(const AItems: TArray<string>; AMax: Integer; const AMore: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AItems) do
  begin
    if Index >= AMax then
    begin
      Result := Result + sLineBreak + Format(AMore, [Length(AItems) - AMax]);
      Break;
    end;
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + AItems[Index];
  end;
end;

end.
