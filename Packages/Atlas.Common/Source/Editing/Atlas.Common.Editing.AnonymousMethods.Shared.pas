unit Atlas.Common.Editing.AnonymousMethods.Shared;

// Gemeinsame Typen und Syntaxhilfen von „In Methode umwandeln“ und „Als anonyme Methode einbetten“ (#680).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.NestedRoutines,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Common.Editing.RoutineParts;

/// <summary>Titel der Code-Aktion „Als anonyme Methode einbetten“.</summary>
function EmbedTitle: string;

type
{$SCOPEDENUMS ON}
  /// <summary>Später laufende anonyme Methode mit erfassten Variablen: Weiterleitung oder Felder.</summary>
  TDeferredCapture = (Forward, Fields);
  /// <summary>Art eines prozeduralen Zieltyps.</summary>
  TProcTypeKind = (Unknown, Reference, MethodPointer, Plain);
  /// <summary>Form an der Stelle: Methodenname, kurze Weiterleitung, Methodenname mit Werten in Feldern.</summary>
  TAnonymousForm = (Direct, Forwarding, Fields);
{$SCOPEDENUMS OFF}

  /// <summary>Art des Typs, an den der Wert AValue geht (Argument, rechte Seite einer Zuweisung, Startwert).
  /// </summary>
  TProcTypeFunc = reference to function(AValue: TSyntaxNode): TProcTypeKind;

  TAnonymousLookup = record
    /// <summary>Typ einer Inline-Variablen ohne Typangabe.</summary>
    InlineType: TPromoteInlineTypeFunc;
    /// <summary>Mitglieder samt Vorfahren (vergebene Namen).</summary>
    MemberExists: TPromoteMemberFunc;
    /// <summary>Steht der Name in der Formulardatei?</summary>
    InForm: TPromoteInFormFunc;
    /// <summary>Record oder Interface (const beim reinen Lesen).</summary>
    ConstType: TConstTypeFunc;
    /// <summary>Zieltyp beim Einbetten; ohne ist er unbekannt.</summary>
    TargetType: TProcTypeFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (Schreiben über var-Argumente).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Aufrufe aus der Datei, Zieltypen und Typen ohne Angabe unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TAnonymousLookup; static;
  end;

  /// <summary>Stelle und Umgebung einer Umwandlung.</summary>
  TAnonymousInput = record
    Text: string;
    Tree: TSyntaxTree;
    Position: TTextPosition;
    Lookup: TAnonymousLookup;
    /// <summary>Form bei später laufenden anonymen Methoden (nur „In Methode umwandeln“).</summary>
    Capture: TDeferredCapture;
    Style: TFormatStyle;
    /// <summary>Eingabe mit Capture Forward und Style Default.</summary>
    class function Create(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TAnonymousLookup): TAnonymousInput; static;
  end;

  /// <summary>Syntaxhilfen beider Richtungen.</summary>
  TAnonymousSyntax = class
  public
    /// <summary>Äußerste Routine um ANode; nil ohne.</summary>
    class function TopRoutineOf(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Liegt ANode (ausschließlich) bis AStop in einer Anweisung der Art AKind?</summary>
    class function Inside(ANode, AStop: TSyntaxNode; AKind: TSyntaxKind): Boolean; static;
    /// <summary>Steht im Bereich von ANode das Schlüsselwort inherited?</summary>
    class function HasInherited(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean; static;
    /// <summary>Ist ANode ein Argument (nicht der Aufgerufene) des Aufrufs AParent?</summary>
    class function IsArgument(ANode, AParent: TSyntaxNode): Boolean; static;
    /// <summary>Hat AOwner Parameter, die ParameterTexts nicht lesen konnte (AParameters leer)?</summary>
    class function UnreadParameters(const AParameters: TArray<TParameterText>;
      AOwner: TSyntaxNode): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSharedText = (EmbedAsAnonymousMethod);

const
  cTexts: array[TSharedText] of TAtlasText = (
    (De: 'Als anonyme Methode einbetten'; En: 'Embed as anonymous method'));

{$SCOPEDENUMS OFF}

function EmbedTitle: string;
begin
  Result := cTexts[TSharedText.EmbedAsAnonymousMethod].Text;
end;

{ TAnonymousLookup }

class function TAnonymousLookup.FromTree(ATree: TSyntaxTree): TAnonymousLookup;
begin
  Result := Default(TAnonymousLookup);
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    Result.Flow := TFlowSignatures.FromTree(ATree.Root);
  end;
end;

{ TAnonymousInput }

class function TAnonymousInput.Create(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TAnonymousLookup): TAnonymousInput;
begin
  Result := Default(TAnonymousInput);
  Result.Text := AText;
  Result.Tree := ATree;
  Result.Position := APosition;
  Result.Lookup := ALookup;
  Result.Capture := TDeferredCapture.Forward;
  Result.Style := TFormatStyle.Default;
end;

{ TAnonymousSyntax }

/// <summary>Äußerste Routine um ANode; nil ohne.</summary>
class function TAnonymousSyntax.TopRoutineOf(ANode: TSyntaxNode): TSyntaxNode;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  mNode := ANode.Parent;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := mNode;
    end;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Liegt ANode (ausschließlich) bis AStop in einer Anweisung der Art AKind?</summary>
class function TAnonymousSyntax.Inside(ANode, AStop: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := False;
  mNode := ANode.Parent;
  while not Result and (mNode <> nil) and (mNode <> AStop) do
  begin
    Result := mNode.Kind = AKind;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Steht im Bereich von ANode das Schlüsselwort inherited?</summary>
class function TAnonymousSyntax.HasInherited(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  while not Result and (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    Result := ATokens[mIndex].IsKeyword('inherited');
    Inc(mIndex);
  end;
end;

/// <summary>Ist ANode ein Argument (nicht der Aufgerufene) des Aufrufs AParent?</summary>
class function TAnonymousSyntax.IsArgument(ANode, AParent: TSyntaxNode): Boolean;
begin
  Result := (AParent <> nil) and (AParent.Kind = TSyntaxKind.Call) and (AParent.ChildCount > 0) and
    (AParent[0] <> ANode);
end;

/// <summary>Hat AOwner Parameter, die ParameterTexts nicht lesen konnte (AParameters leer)?</summary>
class function TAnonymousSyntax.UnreadParameters(const AParameters: TArray<TParameterText>;
  AOwner: TSyntaxNode): Boolean;
var
  mList: TSyntaxNode;
begin
  mList := AOwner.FindChild(TSyntaxKind.Parameters);
  Result := (AParameters = nil) and (mList <> nil) and (mList.ChildCount > 0);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.AnonymousMethods.Shared', cTexts);

end.
