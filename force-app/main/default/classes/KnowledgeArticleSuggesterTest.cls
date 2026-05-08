@isTest
private class KnowledgeArticleSuggesterTest {

    @isTest static void testSuggestForAntCall() {
        Account a = new Account(Name = 'Sandra Reyes Test');
        insert a;
        List<KnowledgeArticleSuggester.ArticleSuggestion> out =
            KnowledgeArticleSuggester.suggest(a.Id, 'I have ants in my kitchen');
        System.assert(!out.isEmpty());
    }

    @isTest static void testSuggestForTermite() {
        Account a = new Account(Name = 'Termite Worry Test');
        insert a;
        List<KnowledgeArticleSuggester.ArticleSuggestion> out =
            KnowledgeArticleSuggester.suggest(a.Id, 'I see termite swarmers near my window');
        System.assert(!out.isEmpty());
        System.assert(out[0].title.containsIgnoreCase('termite'));
    }

    @isTest static void testSuggestEmptyContext() {
        List<KnowledgeArticleSuggester.ArticleSuggestion> out =
            KnowledgeArticleSuggester.suggest(null, '');
        System.assertEquals(0, out.size());
    }
}
