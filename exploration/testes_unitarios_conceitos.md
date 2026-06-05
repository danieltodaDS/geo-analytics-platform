# Conceitos de Testes Unitários em Python

## `with` — Context Manager

O `with` garante que um bloco de código rode dentro de um contexto controlado — com setup antes e teardown depois, mesmo que uma exceção ocorra.

```python
with open("arquivo.txt") as f:
    conteudo = f.read()
# f.close() é chamado automaticamente aqui
```

Por baixo dos panos, o `with` chama dois métodos especiais do objeto:

```python
obj.__enter__()  # antes do bloco
obj.__exit__()   # depois do bloco (sempre, com ou sem erro)
```

É parecido com um CTE no SQL: você compõe o contexto/ambiente antes de executar a operação principal.

---

## `try/except`

O `except` captura e engole exceções lançadas dentro do `try`:

```python
try:
    resultado = 10 / 0
except ZeroDivisionError as e:
    print(str(e))  # "division by zero"
finally:
    print("sempre executa")
```

| Cláusula | Quando executa |
|---|---|
| `try` | sempre |
| `except X` | só se X for lançado |
| `else` | só se nenhuma exceção ocorreu |
| `finally` | sempre, com ou sem exceção |

**Diferença entre `with` e `except`:** o `with` não captura exceções — ele garante o `__exit__`. A exceção continua se propagando. O `except` captura e para a propagação.

---

## `pytest.raises` — Testando Erros Esperados

```python
with pytest.raises(ValidationError):
    _parse(record)
```

A lógica é **invertida** em relação ao que estamos acostumados: o teste **espera o erro** e **falha quando tudo funciona**.

- Exceção lançada → teste passa
- Exceção não lançada → `Failed: DID NOT RAISE <class 'ValidationError'>`

Para também inspecionar a mensagem do erro, usa-se o `as exc_info`:

```python
with pytest.raises(ValidationError) as exc_info:
    _parse(record)

assert "campo obrigatório" in str(exc_info.value)
```

O `exc_info.value` é o objeto da exceção — precisa do `str()` para comparar com texto.

**Para que serve:** garantir que o schema rejeita dados inválidos. Sem esse teste, alguém poderia tornar um campo obrigatório em opcional e o pipeline aceitaria dados ruins silenciosamente.

---

## `MagicMock` — Objeto Falso

`MagicMock()` cria um objeto falso que aceita qualquer coisa sem reclamar:

```python
mock = MagicMock()

mock.qualquer_atributo        # não quebra, retorna outro MagicMock
mock.qualquer_metodo()        # não quebra, retorna outro MagicMock
```

Qualquer atributo de um MagicMock retorna outro MagicMock — são bonecas russas. Cada uma com seu próprio `side_effect` e `return_value`.

```python
mock_resp = MagicMock()
mock_resp.raise_for_status          # MagicMock filho
mock_resp.raise_for_status()        # chama o MagicMock filho
mock_resp.raise_for_status.side_effect  # atributo do MagicMock filho
```

---

## `side_effect` — Comportamento Especial ao Chamar

O `side_effect` é um atributo reservado que o unittest.mock verifica toda vez que o mock é chamado:

```python
def __call__(self, *args, **kwargs):
    if self.side_effect is not None:
        if isinstance(self.side_effect, BaseException):
            raise self.side_effect          # lança a exceção
        elif callable(self.side_effect):
            return self.side_effect(*args)  # chama a função
        else:
            return next(self.side_effect)   # itera sobre lista
    return self.return_value
```

| Tipo do `side_effect` | Comportamento |
|---|---|
| Exceção | lança quando chamado |
| Função | executa e retorna o resultado |
| Lista/iterável | retorna um item por vez a cada chamada |

Quando `side_effect` está definido, o `return_value` é ignorado.

---

## `patch` e `MagicMock` — Como Trabalham Juntos

Não são alternativos — trabalham juntos:

- `patch` — **substitui** o objeto no lugar certo (onde o código de produção o importa)
- `MagicMock` — é o **objeto falso** que o `patch` coloca no lugar

Por padrão, o `patch` já cria um `MagicMock` internamente. O `MagicMock` manual só é necessário quando você precisa configurar comportamentos especiais antes de passar para o `patch`.

```python
# patch simples — suficiente para simular retorno feliz
patch("requests.get", return_value=mock_resp)

# MagicMock manual — quando precisa simular erros
mock_resp = MagicMock()
mock_resp.raise_for_status.side_effect = requests.HTTPError(response=mock_resp)
patch("requests.get", return_value=mock_resp)
```

---

## Restrições de Nomenclatura

Ao nomear atributos de um mock, há duas restrições distintas:

- **`side_effect`** — restrito pelo **unittest.mock**: é o nome que o framework procura internamente para executar o comportamento especial. Trocar por outro nome quebra a funcionalidade.

- **`raise_for_status`** — restrito pelo **código de produção**: o mock substitui um objeto `requests.Response` real, que tem esse método. O código de produção chama `response.raise_for_status()`, então o mock precisa ter o mesmo nome. Trocar por outro nome faz o mock ser ignorado.

---

## Unpacking de Dicionário com Override

```python
{**SIDRA_RECORD, "V": "-"}
```

Espalha todos os pares de `SIDRA_RECORD` no novo dicionário e sobrescreve a chave `"V"`. Útil para criar variações de um registro base nos testes sem modificar o original.

Equivalente a:

```python
novo = SIDRA_RECORD.copy()
novo["V"] = "-"
```
