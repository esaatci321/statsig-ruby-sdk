# typed: false

require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'statsig_user'
require_relative './dummy_data_adapter'

class StatsigDataAdapterTest < Minitest::Test
  def setup
    super
    WebMock.enable!
    @json_file = File.read("#{__dir__}/data/download_config_specs.json")
    @mock_response = JSON.parse(@json_file).to_json

    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200)
    @user = StatsigUser.new({ 'userID' => 'a_user' })
    @user_in_idlist_1 = StatsigUser.new({ 'userID' => 'a-user' })
    @user_in_idlist_2 = StatsigUser.new({ 'userID' => 'b-user' })
    @user_not_in_idlist = StatsigUser.new({ 'userID' => 'c-user' })
  end

  def teardown
    super
    WebMock.disable!
  end

  def test_datastore
    options = StatsigOptions.new
    options.local_mode = true
    options.data_store = DummyDataAdapter.new
    driver = StatsigDriver.new('secret-testcase', options)
    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)
  end

  def test_datastore_overwritten_by_network
    options = StatsigOptions.new(rulesets_sync_interval: 1)
    options.data_store = DummyDataAdapter.new
    driver = StatsigDriver.new('secret-testcase', options)

    sleep 2

    adapter = options.data_store&.get("statsig.cache")
    adapter_json = JSON.parse(adapter)
    assert(adapter_json == JSON.parse(@mock_response))
    assert(adapter_json["feature_gates"].size === 4)
    assert(adapter_json["feature_gates"][0]["name"] === "email_not_null")

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == false)

    result = driver.get_config(@user, "test_config")
    assert(result.get("number", 3) == 4)

    result = driver.check_gate(@user, "always_on_gate")
    assert(result == true)
  end

  def test_datastore_and_bootstrap_ignores_bootstrap
    options = StatsigOptions.new
    options.data_store = DummyDataAdapter.new
    options.bootstrap_values = @mock_response
    options.local_mode = true
    driver = StatsigDriver.new('secret-testcase', options)
    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)

    result = driver.check_gate(@user, "always_on_gate")
    assert(result == false)
  end

  def test_datastore_used_for_polling
    options = StatsigOptions.new(rulesets_sync_interval: 1, idlists_sync_interval: 1, local_mode: true)
    options.data_store = DummyDataAdapter.new(poll_config_specs: true, poll_id_lists: true)
    driver = StatsigDriver.new('secret-testcase', options)

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == true)
    result = driver.check_gate(@user_in_idlist_2, "test_id_list")
    assert(result == true)
    result = driver.check_gate(@user_not_in_idlist, "test_id_list")
    assert(result == false)

    options.data_store.remove_feature_gate("gate_from_adapter")
    options.data_store.update_id_lists

    sleep 1

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == false)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == false)
    result = driver.check_gate(@user_in_idlist_2, "test_id_list")
    assert(result == false)
    result = driver.check_gate(@user_not_in_idlist, "test_id_list")
    assert(result == true)
  end

  def test_datastore_fallback_to_network
    options = StatsigOptions.new(rulesets_sync_interval: 1, idlists_sync_interval: 1)
    options.data_store = DummyDataAdapter.new(poll_config_specs: true, poll_id_lists: true)
    driver = StatsigDriver.new('secret-testcase', options)

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == true)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == true)

    options.data_store.corrupt_store

    sleep 1

    result = driver.check_gate(@user, "gate_from_adapter")
    assert(result == false)
    result = driver.check_gate(@user_in_idlist_1, "test_id_list")
    assert(result == false)
    result = driver.check_gate(@user, "always_on_gate")
    assert(result == true)
  end
end
