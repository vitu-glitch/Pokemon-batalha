POKEBRAWL - IMPORTACAO DA PRIMEIRA GERACAO

1. Feche o Godot.
2. Na pasta raiz do repositorio, execute IMPORT_GEN1.bat.
3. Aguarde o download e a conversao dos modelos. Na primeira atualizacao, os 140 modelos importados anteriormente serao reconstruidos.
4. Abra a pasta game no Godot e execute o projeto.

O importador:
- baixa os assets da revisao fixada no manifesto;
- converte geometria e animacoes Bedrock para model.json.gz;
- copia textura normal e shiny;
- cria game/pokemon/gen1_species.json com tipos, stats, habilidades e learnsets;
- preserva os 11 modelos originais e reconstroi automaticamente os modelos importados por versoes antigas do conversor.

Os golpes sao escolhidos apenas entre os scripts ja implementados no PokeBrawl.
Alguns Pokemon com poucas opcoes prontas recebem golpes de reserva funcionais.
Habilidades sem efeito programado ficam com "No active ability" ate receberem implementacao.

Os assets importados sao atribuidos ao Cobblemon e estao sujeitos a CC BY-NC 3.0.
Consulte game/pokemon/LICENSE-models.txt. A licenca proibe usos principalmente comerciais
sem permissao separada dos titulares.
