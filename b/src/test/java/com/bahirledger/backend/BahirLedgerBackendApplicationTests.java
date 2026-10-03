package com.bahirledger.backend;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@SpringBootTest
@Import(AuthTestConfiguration.class)
class BahirLedgerBackendApplicationTests {

	@Test
	void contextLoads() {
	}

}
