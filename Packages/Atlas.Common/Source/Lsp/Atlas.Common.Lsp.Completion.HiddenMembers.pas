unit Atlas.Common.Lsp.Completion.HiddenMembers;

// Mitglieder, die nach "X.Pr" nur wegen ihrer Sichtbarkeit fehlen (#2108): Die Namensauflösung merkt sie beim
// Sammeln der Mitglieder (TResolverCandidates.KeepHidden), diese Unit macht daraus den Zusatz "hiddenMembers"
// der CompletionList. Er steht neben den Einträgen, nicht in ihnen: Andere Editoren zeigen ihn nicht, Atlas nennt
// ihn in der Fußzeile und zeigt ihn erst auf Wunsch ausgegraut. Mit "uri", "line" und "character" der
// Deklaration holt das Plugin über atlas.server.memberActions die Aktionen für einen gewählten Eintrag.

interface

uses
  System.JSON,
  Atlas.Common.Semantics.NameResolver.Candidates,
  Atlas.Common.Lsp.CompletionRequest;

type
  TCompletionHiddenMembers = class
  public const
    /// <summary>So viele nicht sichtbare Mitglieder liefert der Server höchstens; die Zahl nennt alle.</summary>
    cMaxMembers = 50;
  public
    /// <summary>Soll die Anfrage nicht sichtbare Mitglieder sammeln? Nur mit completion.hiddenMembers und einem
    /// getippten Präfix, damit die Fußzeile nicht bei jeder Liste etwas meldet.</summary>
    class function Wanted(ARequest: TCompletionRequest; const APrefix: string): Boolean; static;
    /// <summary>Die gemerkten Mitglieder der Namensauflösung, nach Name sortiert.</summary>
    class function FromResolver(const AHidden: TArray<THiddenMember>): TArray<TCompletionHiddenMember>; static;
    /// <summary>Schreibt "hiddenMembers" (count, items) in die CompletionList AList; nichts ohne Mitglieder.
    /// </summary>
    class procedure WriteJson(AList: TJSONObject; const AMembers: TArray<TCompletionHiddenMember>); static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.CompletionCollector;

const
  cVisibilities: array[TIndexVisibility] of string = ('public', 'published', 'protected', 'strict protected',
    'private', 'strict private');

/// <summary>Klassenname ohne Unit davor ("Atlas.Core.Usage.TAtlasUsage" → "TAtlasUsage").</summary>
function ShortContainer(const AContainer, AUnitName: string): string;
begin
  Result := AContainer;
  if (AUnitName <> '') and SameText(Copy(Result, 1, Length(AUnitName) + 1), AUnitName + '.') then
  begin
    Result := Copy(Result, Length(AUnitName) + 2, MaxInt);
  end;
end;

function ToMember(const AHidden: THiddenMember): TCompletionHiddenMember;
begin
  Result := Default(TCompletionHiddenMember);
  Result.Name := AHidden.Symbol.Name;
  Result.Kind := CompletionKindOf(AHidden.Symbol.SymbolKind);
  Result.Visibility := cVisibilities[AHidden.Symbol.Visibility];
  Result.Container := ShortContainer(AHidden.Symbol.Container, AHidden.Symbol.UnitName);
  Result.Detail := AHidden.Symbol.Signature;
  Result.UnitName := AHidden.Symbol.UnitName;
  Result.FileName := AHidden.Symbol.FileName;
  Result.Line := AHidden.Symbol.SelectionRange.StartPos.Line;
  Result.Character := AHidden.Symbol.SelectionRange.StartPos.Character;
  Result.External := AHidden.External;
end;

{ TCompletionHiddenMembers }

class function TCompletionHiddenMembers.Wanted(ARequest: TCompletionRequest; const APrefix: string): Boolean;
begin
  Result := ARequest.Settings.HiddenMembers and (APrefix <> '');
end;

class function TCompletionHiddenMembers.FromResolver(
  const AHidden: TArray<THiddenMember>): TArray<TCompletionHiddenMember>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AHidden));
  for mIndex := 0 to High(AHidden) do
  begin
    Result[mIndex] := ToMember(AHidden[mIndex]);
  end;
  // Eindeutig: Namen sind je Liste einmalig (HiddenToArray).
  TArray.Sort<TCompletionHiddenMember>(Result, TComparer<TCompletionHiddenMember>.Construct(
    function(const A, B: TCompletionHiddenMember): Integer
    begin
      Result := CompareText(A.Name, B.Name);
    end));
end;

class procedure TCompletionHiddenMembers.WriteJson(AList: TJSONObject;
  const AMembers: TArray<TCompletionHiddenMember>);
var
  mHidden: TJSONObject;
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIndex: Integer;
begin
  if (AList = nil) or (Length(AMembers) = 0) then
  begin
    Exit;
  end;
  mItems := TJSONArray.Create;
  for mIndex := 0 to High(AMembers) do
  begin
    if mIndex >= cMaxMembers then
    begin
      Break;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('name', AMembers[mIndex].Name);
    mItem.AddPair('kind', TJSONNumber.Create(AMembers[mIndex].Kind));
    mItem.AddPair('visibility', AMembers[mIndex].Visibility);
    mItem.AddPair('container', AMembers[mIndex].Container);
    if AMembers[mIndex].Detail <> '' then
    begin
      mItem.AddPair('detail', AMembers[mIndex].Detail);
    end;
    mItem.AddPair('unit', AMembers[mIndex].UnitName);
    // Datei der Deklaration für die Aktionen „Sichtbarkeit anheben“ und „Eigenschaft anlegen“
    // (atlas.server.memberActions); fehlt ohne bekannte Datei.
    if AMembers[mIndex].FileName <> '' then
    begin
      mItem.AddPair('uri', TDocumentUris.FromPath(AMembers[mIndex].FileName));
    end;
    mItem.AddPair('line', TJSONNumber.Create(AMembers[mIndex].Line));
    mItem.AddPair('character', TJSONNumber.Create(AMembers[mIndex].Character));
    mItem.AddPair('external', TJSONBool.Create(AMembers[mIndex].External));
    mItems.AddElement(mItem);
  end;
  mHidden := TJSONObject.Create;
  mHidden.AddPair('count', TJSONNumber.Create(Length(AMembers)));
  mHidden.AddPair('items', mItems);
  AList.AddPair('hiddenMembers', mHidden);
end;

end.
