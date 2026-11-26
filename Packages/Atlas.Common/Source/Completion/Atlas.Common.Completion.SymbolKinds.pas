unit Atlas.Common.Completion.SymbolKinds;

// Art eines Eintrags der Vervollständigung (CompletionItemKind des LSP, Konstanten cKind… in
// Atlas.Common.Completion.Contract) zur Art eines Symbols im Index; geteilt von Sprachserver und Editing.

interface

uses
  Atlas.Common.Index.Contract;

/// <summary>CompletionItemKind des LSP zur Symbolart.</summary>
function CompletionKindOf(AKind: TIndexSymbolKind): Integer;

implementation

uses
  Atlas.Common.Completion.Contract;

function CompletionKindOf(AKind: TIndexSymbolKind): Integer;
begin
  case AKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias:
      Result := cKindClass;
    TIndexSymbolKind.RecordType:
      Result := cKindStruct;
    TIndexSymbolKind.InterfaceType:
      Result := cKindInterface;
    TIndexSymbolKind.EnumType:
      Result := cKindEnum;
    TIndexSymbolKind.EnumMember:
      Result := cKindEnumMember;
    TIndexSymbolKind.Constant:
      Result := cKindConstant;
    TIndexSymbolKind.Field:
      Result := cKindField;
    TIndexSymbolKind.Property_:
      Result := cKindProperty;
    TIndexSymbolKind.Method:
      Result := cKindMethod;
    TIndexSymbolKind.Constructor_:
      Result := cKindConstructor;
    TIndexSymbolKind.Routine:
      Result := cKindFunction;
  else
    Result := cKindVariable;
  end;
end;

end.
