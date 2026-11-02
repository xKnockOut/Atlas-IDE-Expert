unit Atlas.Core.Completion.Providers.XmlDoc;

// XMLDoc-Tags in ///-Kommentaren (#435): Nach "/// <" schlägt Atlas die Tags
// vor, bei <param> je Parameter der folgenden Deklaration einen Eintrag,
// <returns> nur bei Funktionen. Lokal, ohne Server. Der Einfügetext markiert
// mit "$0", wo der Cursor danach steht (zwischen den Tags).

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Internals.Async;

type
  TAtlasXmlDoc = class
  public
    /// <summary>Steht der Cursor nach "/// &lt;" (ggf. mit angefangenem Tag)? ALineBefore: Zeile bis zum Cursor.</summary>
    class function IsTagContext(const ALineBefore: string): Boolean; static;
    /// <summary>Deklaration nach der Zeile ALine (0-basiert): die nächsten Zeilen ohne ///, bis ";"
    /// außerhalb von Klammern; '' ohne.</summary>
    class function FollowingDeclaration(const AText: string; ALine: Integer): string; static;
    /// <summary>Parameternamen einer Deklaration in Reihenfolge.</summary>
    class function ParamNames(const ADeclaration: string): TArray<string>; static;
    /// <summary>Vorschläge für ADeclaration.</summary>
    class function TagItems(const ADeclaration: string): TAtlasCompletionItems; static;
  end;

  TAtlasXmlDocCompletionProvider = class(TAtlasAsyncCompletionProvider)
  public const
    /// <summary>Name für die Sicherung je Quelle (#493).</summary>
    ProviderTitle = 'Vervollständigung (XMLDoc)';
  public
    constructor Create;
  protected
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Classes;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function Tag(const AName, AInsert: string; ARank: Integer): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
  Result.InsertText := AInsert;
  Result.Kind := TAtlasItemKind.XmlDocTag;
  Result.Rank := ARank;
  Result.UnitUsed := True;
end;

{ TAtlasXmlDoc }

class function TAtlasXmlDoc.IsTagContext(const ALineBefore: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if not TrimLeft(ALineBefore).StartsWith('///') then
    Exit;
  // Angefangenen Tagnamen überspringen, dann muss "<" stehen.
  Index := Length(ALineBefore);
  while (Index > 0) and CharInSet(ALineBefore[Index], ['A'..'Z', 'a'..'z']) do
    Dec(Index);
  Result := (Index > 0) and (ALineBefore[Index] = '<');
end;

class function TAtlasXmlDoc.FollowingDeclaration(const AText: string; ALine: Integer): string;
var
  All: TArray<string>;
  Index, Depth, Position: Integer;
  Line: string;
begin
  Result := '';
  All := Lines(AText);
  Depth := 0;
  for Index := ALine + 1 to Min(High(All), ALine + 12) do
  begin
    Line := Trim(All[Index]);
    if Line.StartsWith('///') or ((Result = '') and ((Line = '') or Line.StartsWith('['))) then
      Continue;
    Result := Result + ' ' + Line;
    for Position := 1 to Length(Line) do
      case Line[Position] of
        '(': Inc(Depth);
        ')': Dec(Depth);
        ';':
          if Depth <= 0 then
            Exit(Trim(Result));
      end;
  end;
  Result := Trim(Result);
end;

class function TAtlasXmlDoc.ParamNames(const ADeclaration: string): TArray<string>;
var
  Open, Close, Index: Integer;
  Inner, Group, Names, Name: string;
begin
  Result := nil;
  Open := Pos('(', ADeclaration);
  if Open = 0 then
    Exit;
  Close := Open;
  Index := 0;
  repeat
    case ADeclaration[Close] of
      '(': Inc(Index);
      ')': Dec(Index);
    end;
    Inc(Close);
  until (Index = 0) or (Close > Length(ADeclaration));
  Inner := Copy(ADeclaration, Open + 1, Close - Open - 2);
  for Group in Inner.Split([';']) do
  begin
    // "const A, B: string = ''" → A, B
    Names := Group;
    if Pos(':', Names) > 0 then
      Names := Copy(Names, 1, Pos(':', Names) - 1);
    Names := Trim(Names);
    for Name in ['const ', 'var ', 'out ', 'constref '] do
      if StartsText(Name, Names) then
        Names := Trim(Copy(Names, Length(Name) + 1, MaxInt));
    for Name in Names.Split([',']) do
      if Trim(Name) <> '' then
        Result := Result + [Trim(Name)];
  end;
end;

class function TAtlasXmlDoc.TagItems(const ADeclaration: string): TAtlasCompletionItems;
var
  Name: string;
  Rank: Integer;
  IsFunction: Boolean;
begin
  Rank := 0;
  Result := [Tag('summary', 'summary>$0</summary>', Rank)];
  for Name in ParamNames(ADeclaration) do
  begin
    Inc(Rank);
    Result := Result + [Tag(Format('param name="%s"', [Name]), Format('param name="%s">$0</param>', [Name]), Rank)];
  end;
  IsFunction := StartsText('function ', TrimLeft(ADeclaration)) or StartsText('class function ', TrimLeft(ADeclaration));
  if IsFunction then
    Result := Result + [Tag('returns', 'returns>$0</returns>', Rank + 1)];
  Result := Result + [Tag('remarks', 'remarks>$0</remarks>', Rank + 2),
    Tag('exception cref=""', 'exception cref="$0"></exception>', Rank + 3),
    Tag('see cref=""', 'see cref="$0"/>', Rank + 4), Tag('value', 'value>$0</value>', Rank + 5),
    Tag('para', 'para>$0</para>', Rank + 6), Tag('c', 'c>$0</c>', Rank + 7),
    Tag('code', 'code>$0</code>', Rank + 8)];
end;

{ TAtlasXmlDocCompletionProvider }

constructor TAtlasXmlDocCompletionProvider.Create;
begin
  inherited Create;
  Name := ProviderTitle;
end;

function TAtlasXmlDocCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems;
var
  All: TArray<string>;
begin
  AState := Default(TAtlasFetchState);
  Result := nil;
  All := Lines(AContext.Text);
  if (AContext.Line < 0) or (AContext.Line > High(All)) then
    Exit;
  if not TAtlasXmlDoc.IsTagContext(Copy(All[AContext.Line], 1, AContext.Character)) then
    Exit;
  Result := TAtlasXmlDoc.TagItems(TAtlasXmlDoc.FollowingDeclaration(AContext.Text, AContext.Line));
end;

end.
